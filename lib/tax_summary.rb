require 'json'
require_relative 'quaderno_client'
require_relative 'date_helper'

class TaxSummary
  EU_COUNTRIES = %w[AT BE BG HR CY CZ DK EE FI FR DE GR HU IE IT LV LT LU MT NL PL PT RO SK SI SE].freeze

  def initialize(quarter:)
    @from, @to = DateHelper.parse_range(quarter: quarter)
    @year = @to.year
    @quarter_num = quarter.to_s.match(/Q(\d)/i)[1].to_i
    @company_country = ENV.fetch('COMPANY_COUNTRY', 'ES')
    @vat_rate = ENV.fetch('VAT_RATE', '21').to_f
    @stripe_vat_id = ENV['STRIPE_VAT_ID']
    @dropbox_folder = ENV['DROPBOX_FOLDER']
    @company_name = ENV['COMPANY_NAME']
  end

  def generate
    fetch_data

    result = {
      period: {
        quarter: "Q#{@quarter_num}",
        year: @year,
        from: @from.to_s,
        to: @to.to_s
      },
      data_counts: {
        invoices: @invoices.length,
        expenses: @expenses.length,
        credits: @credits.length
      },
      modelo_111: compute_modelo_111,
      modelo_303: compute_modelo_303,
      modelo_349: compute_modelo_349,
      modelo_369: compute_modelo_369
    }

    stripe = compute_stripe_fees
    result[:stripe_fees] = stripe if stripe

    result
  end

  private

  # ---- Data fetching ----

  def fetch_data
    client = QuadernoClient.new
    @invoices = client.list_invoices(from: @from, to: @to)
    @expenses = client.list_expenses(from: @from, to: @to)
    @credits = client.list_credits(from: @from, to: @to)
    $stderr.puts "Fetched #{@invoices.length} invoices, #{@expenses.length} expenses, #{@credits.length} credits"
  end

  # ---- EUR conversion ----

  def to_eur(amount_cents, currency, exchange_rate)
    amount = amount_cents.to_f / 100.0
    (currency == "EUR" || exchange_rate.to_f.zero?) ? amount : amount * exchange_rate.to_f
  end

  # ---- Classification ----

  def classify_invoice(inv)
    country = inv["country"]
    has_vat = inv["taxes"]&.any? { |t| t["rate"].to_f > 0 }

    if country == @company_country
      :domestic
    elsif EU_COUNTRIES.include?(country)
      has_vat ? :eu_b2c_oss : :eu_b2b
    else
      :non_eu
    end
  end

  def classify_expense(exp)
    country = exp["country"]
    has_iva = exp["taxes"]&.any? { |t| t["name"] != "IRPF" && t["rate"].to_f > 0 }

    if country == @company_country
      :domestic
    elsif EU_COUNTRIES.include?(country)
      has_iva ? :domestic : :eu_intra # EU supplier charging IVA = domestic treatment
    else
      :non_eu
    end
  end

  # ---- Modelo 111: IRPF withholdings ----

  def compute_modelo_111
    irpf_expenses = @expenses.select { |e| e["taxes"]&.any? { |t| t["name"] == "IRPF" } }

    contacts = {}
    irpf_expenses.each do |exp|
      name = exp.dig("contact", "full_name") || "Unknown"
      contacts[name] ||= { percepciones: 0.0, retenciones: 0.0 }

      exp["taxes"].each do |t|
        next unless t["name"] == "IRPF"
        contacts[name][:percepciones] += to_eur(t["taxable_base_cents"].to_i, exp["currency"], exp["exchange_rate"])
        contacts[name][:retenciones] += to_eur(t["amount_cents"].to_i.abs, exp["currency"], exp["exchange_rate"])
      end
    end

    total_perc = contacts.values.sum { |c| c[:percepciones] }
    total_ret = contacts.values.sum { |c| c[:retenciones] }

    {
      box_07_perceptores: contacts.length,
      box_08_percepciones: total_perc.round(2),
      box_09_retenciones: total_ret.round(2),
      box_30_resultado: total_ret.round(2),
      contacts: contacts.transform_values { |v|
        { percepciones: v[:percepciones].round(2), retenciones: v[:retenciones].round(2) }
      }
    }
  end

  # ---- Modelo 303: quarterly VAT ----

  def compute_modelo_303
    inv_by_type = @invoices.group_by { |i| classify_invoice(i) }
    cred_by_type = @credits.group_by { |c| classify_invoice(c) }
    exp_by_type = @expenses.group_by { |e| classify_expense(e) }

    # Sales
    eu_b2b_sales = sum_totals(inv_by_type[:eu_b2b]) - sum_totals(cred_by_type[:eu_b2b])
    non_eu_sales = sum_totals(inv_by_type[:non_eu]) - sum_totals(cred_by_type[:non_eu])
    oss_base = sum_subtotals(inv_by_type[:eu_b2c_oss])

    # Expenses
    eu_intra_base = sum_totals(exp_by_type[:eu_intra])
    non_eu_exp_base = sum_totals(exp_by_type[:non_eu])
    dom_base, dom_iva = domestic_expense_iva(exp_by_type[:domestic])

    # Stripe fees (EU intra-community, not in Quaderno)
    stripe_total = compute_stripe_fees&.dig(:total_eur) || 0.0
    eu_intra_with_stripe = eu_intra_base + stripe_total

    eu_intra_iva = (eu_intra_with_stripe * @vat_rate / 100).round(2)
    non_eu_iva = (non_eu_exp_base * @vat_rate / 100).round(2)
    total_devengado = (eu_intra_iva + non_eu_iva).round(2)
    total_deducible = (dom_iva + eu_intra_iva).round(2)

    {
      iva_devengado: {
        box_10_eu_intra_base: eu_intra_with_stripe.round(2),
        box_10_quaderno_only: eu_intra_base.round(2),
        box_10_stripe_component: stripe_total.round(2),
        box_11_eu_intra_iva: eu_intra_iva,
        box_12_non_eu_base: non_eu_exp_base.round(2),
        box_13_non_eu_iva: non_eu_iva,
        box_27_total_devengado: total_devengado
      },
      iva_deducible: {
        box_28_pure_domestic_base: dom_base.round(2),
        box_29_pure_domestic_iva: dom_iva.round(2),
        box_29_iva_check: (dom_base * @vat_rate / 100).round(2),
        box_36_eu_intra_base: eu_intra_with_stripe.round(2),
        box_37_eu_intra_iva: eu_intra_iva,
        box_45_total_deducible: total_deducible,
        box_46_result: (total_devengado - total_deducible).round(2)
      },
      informacion_adicional: {
        box_59_eu_b2b_sales: eu_b2b_sales.round(2),
        box_120_non_eu_sales: non_eu_sales.round(2),
        box_123_oss: oss_base.round(2)
      }
    }
  end

  # ---- Modelo 349: EU intra-community operators ----

  def compute_modelo_349
    eu_b2b_invoices = @invoices.select { |i| classify_invoice(i) == :eu_b2b }
    eu_intra_expenses = @expenses.select { |e| classify_expense(e) == :eu_intra }

    clave_s = aggregate_by_contact(eu_b2b_invoices)
    clave_i = aggregate_by_contact(eu_intra_expenses)

    stripe = compute_stripe_fees
    if stripe && @stripe_vat_id
      country = @stripe_vat_id[0..1]
      clave_i << {
        vat_id: @stripe_vat_id,
        name: "Stripe Payments Europe Limited",
        country: country,
        amount: stripe[:total_eur].round(2),
        source: "stripe_pdfs"
      }
    end

    total_s = clave_s.sum { |e| e[:amount] }
    total_i = clave_i.sum { |e| e[:amount] }

    {
      clave_s: clave_s,
      clave_i: clave_i,
      total_s: total_s.round(2),
      total_i: total_i.round(2),
      grand_total: (total_s + total_i).round(2),
      operator_count: clave_s.length + clave_i.length
    }
  end

  # ---- Modelo 369: OSS / Ventanilla Unica ----

  def compute_modelo_369
    oss_invoices = @invoices.select { |i| classify_invoice(i) == :eu_b2c_oss }

    by_country = {}
    oss_invoices.each do |inv|
      country = inv["country"]
      country = "EL" if country == "GR" # Greece code in modelos
      base = to_eur(inv["subtotal_cents"].to_i, inv["currency"], inv["exchange_rate"])
      vat = inv["taxes"]&.sum { |t| to_eur(t["amount_cents"].to_i, inv["currency"], inv["exchange_rate"]) } || 0
      rate = inv["taxes"]&.first&.dig("rate").to_f

      by_country[country] ||= { base: 0.0, vat: 0.0, rate: rate, invoices: 0 }
      by_country[country][:base] += base
      by_country[country][:vat] += vat
      by_country[country][:invoices] += 1
    end

    countries = by_country.sort.map do |code, data|
      {
        country: code,
        rate: data[:rate],
        base: data[:base].round(2),
        vat: data[:vat].round(2),
        arithmetic_check: (data[:base] * data[:rate] / 100).round(2),
        invoices: data[:invoices]
      }
    end

    {
      countries: countries,
      total_base: by_country.values.sum { |d| d[:base] }.round(2),
      total_vat: by_country.values.sum { |d| d[:vat] }.round(2)
    }
  end

  # ---- Stripe fee extraction from PDFs ----

  def compute_stripe_fees
    return @stripe_fees if defined?(@stripe_fees)

    paths = stripe_invoice_paths
    return @stripe_fees = nil if paths.empty?

    require 'pdf/reader'

    months = []
    total = 0.0

    paths.each do |path|
      text = PDF::Reader.new(path).pages.map(&:text).join("\n")
      match = text.match(/Total fees in EUR\s+€?([\d.,]+)/)
      next unless match

      amount = match[1].delete(',').to_f
      months << { file: File.basename(path), eur: amount.round(2) }
      total += amount
    end

    @stripe_fees = { months: months, total_eur: total.round(2) }
  end

  def stripe_invoice_paths
    return [] unless @dropbox_folder && @company_name

    template = ENV['STRIPE_INVOICE_PATH']

    quarter_months.flat_map do |month|
      mm = month.to_s.rjust(2, '0')
      pattern = if template
                  template.gsub('{year}', @year.to_s).gsub('{month}', mm)
                else
                  File.join(
                    @dropbox_folder, @year.to_s,
                    "#{@year} - #{mm} #{@company_name} Taxes",
                    "Stripe Tax Invoice *.pdf"
                  )
                end
      Dir.glob(pattern)
    end.sort
  end

  def quarter_months
    start = (@quarter_num - 1) * 3 + 1
    (start..start + 2).to_a
  end

  # ---- Aggregation helpers ----

  def sum_totals(items)
    (items || []).sum { |i| to_eur(i["total_cents"].to_i, i["currency"], i["exchange_rate"]) }
  end

  def sum_subtotals(items)
    (items || []).sum { |i| to_eur(i["subtotal_cents"].to_i, i["currency"], i["exchange_rate"]) }
  end

  def domestic_expense_iva(expenses)
    base = 0.0
    iva = 0.0
    (expenses || []).each do |exp|
      exp["taxes"]&.each do |t|
        next if t["name"] == "IRPF"
        base += to_eur(t["taxable_base_cents"].to_i, exp["currency"], exp["exchange_rate"])
        iva += to_eur(t["amount_cents"].to_i, exp["currency"], exp["exchange_rate"])
      end
    end
    [base, iva]
  end

  def aggregate_by_contact(records)
    groups = {}
    records.each do |rec|
      name = rec.dig("contact", "full_name") || "Unknown"
      vat_id = rec["tax_id"] || ""
      key = vat_id.empty? ? name : vat_id
      amount = to_eur(rec["total_cents"].to_i, rec["currency"], rec["exchange_rate"])

      groups[key] ||= { name: name, vat_id: vat_id, country: rec["country"], amount: 0.0 }
      groups[key][:amount] += amount
    end

    groups.values
      .map { |d| { vat_id: d[:vat_id], name: d[:name], country: d[:country], amount: d[:amount].round(2) } }
      .sort_by { |e| [e[:country], e[:name]] }
  end
end
