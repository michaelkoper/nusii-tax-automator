require 'faraday'
require 'json'
require 'base64'
require 'fileutils'
require_relative 'contacts'

class QuadernoClient
  def initialize
    @api_key = ENV['QUADERNO_API_KEY']
    @api_url = ENV['QUADERNO_API_URL']
    @email_attachments_folder = ENV['EMAIL_ATTACHMENTS_FOLDER']
    @dropbox_folder = ENV['DROPBOX_FOLDER']
    @temp_dir = File.join(ENV['CODE_ROOT'] || File.expand_path('..', __dir__), 'temp')

    @connection = Faraday.new(url: @api_url) do |faraday|
      faraday.request :json
      faraday.response :json
      faraday.request :authorization, :basic, @api_key, 'x'
      faraday.adapter Faraday.default_adapter
    end
  end

  # ---- List resources (with optional date filtering and auto-pagination) ----

  def list_invoices(from: nil, to: nil)
    list_all('invoices', date_params(from, to))
  end

  def list_expenses(from: nil, to: nil)
    list_all('expenses', date_params(from, to))
  end

  def list_credits(from: nil, to: nil)
    list_all('credits', date_params(from, to))
  end

  def list_contacts(q: nil)
    params = {}
    params[:q] = q if q
    list_all('contacts', params)
  end

  # ---- Get single resource by ID ----

  def get_invoice(id)
    get_resource('invoices', id)
  end

  def get_expense(id)
    get_resource('expenses', id)
  end

  def get_credit(id)
    get_resource('credits', id)
  end

  def get_contact(id)
    get_resource('contacts', id)
  end

  # ---- Existing public methods ----

  def upload_expenses
    expenses_file = File.join(@temp_dir, 'expenses.json')

    unless File.exist?(expenses_file)
      puts 'No expenses.json file found. Run PDF processor first.'
      return
    end

    expenses = JSON.parse(File.read(expenses_file))

    expenses.each do |expense|
      category = expense['category'].to_sym
      details = Contacts.all[category] || {}

      if details.empty?
        puts "Warning: No category details found for #{category}. Skipping..."
        next
      end

      expense_data = build_expense_data(expense, details)

      puts "Creating expense for #{category}..."
      response = create_expense(expense_data)

      if response['error']
        puts "Error creating expense for #{category}: #{response['error']}"
        next
      else
        puts "Expense for #{category} created successfully"
        move_processed_file(expense)
      end
    end
  end

  def create_contact(attributes)
    response = @connection.post('contacts', attributes)

    if response.status == 201
      $stderr.puts "Contact created: #{response.body['full_name']} (id: #{response.body['id']})"
    else
      $stderr.puts "Error creating contact: #{response.body}"
    end

    response.body
  rescue Faraday::Error => e
    $stderr.puts "HTTP Error: #{e.message}"
    { 'error' => e.message }
  end

  private

  # ---- Query helpers ----

  def date_params(from, to)
    params = {}
    if from && to
      params[:date] = "#{from},#{to}"
    elsif from
      params[:date] = "#{from},2099-12-31"
    elsif to
      params[:date] = "2000-01-01,#{to}"
    end
    params
  end

  def list_all(endpoint, params = {})
    results = []
    next_url = nil

    loop do
      response = if next_url
                   @connection.get(next_url)
                 else
                   @connection.get(endpoint, params)
                 end

      unless response.success?
        raise "Quaderno API error (#{response.status}): #{response.body}"
      end

      batch = response.body
      break if !batch.is_a?(Array) || batch.empty?

      results.concat(batch)

      has_more = response.headers['x-pages-hasmore']
      break unless has_more == 'true'

      next_url = response.headers['x-pages-nextpage']
      break unless next_url

      # Strip the base URL if present — Faraday needs a relative path
      next_url = next_url.sub(@api_url.to_s, '')
    end
    results
  end

  def get_resource(endpoint, id)
    response = @connection.get("#{endpoint}/#{id}")

    unless response.success?
      raise "Quaderno API error (#{response.status}): #{response.body}"
    end

    response.body
  end

  # ---- Expense building ----

  def build_expense_data(expense, details)
    item = {
      description: details[:item_description],
      unit_price: expense['pre_tax_price']
    }

    # Add Spanish VAT if applicable
    if expense['tax_percentage'] == 21
      item.merge!({
                    tax_1_transaction_type: 'standard',
                    tax_1_country: 'ES',
                    tax_1_name: 'IVA',
                    tax_1_rate: 21
                  })
    end

    # Add Spanish retention if applicable
    if expense['retencion_percentage'] == 15
      item.merge!({
                    tax_2_transaction_type: 'retention',
                    tax_2_country: 'ES',
                    tax_2_name: 'IRPF',
                    tax_2_rate: -15
                  })
    end

    {
      contact: {
        id: details[:contact_id],
        full_name: details[:contact_full_name]
      },
      issue_date: expense['date'],
      currency: expense['currency'],
      items: [item],
      payment_method: details[:payment_method],
      attachment: {
        filename: expense['filename'],
        data: encode_file(File.join(@email_attachments_folder, expense['filename']))
      }
    }
  end

  def encode_file(filepath)
    return nil unless File.exist?(filepath)

    Base64.encode64(File.read(filepath, mode: 'rb'))
  end

  def create_expense(expense_data)
    response = @connection.post('expenses', expense_data)
    response.body
  rescue Faraday::Error => e
    puts "HTTP Error: #{e.message}"
    { 'error' => e.message }
  end

  def move_processed_file(expense)
    date_parts = expense['date'].split('-')
    year = date_parts[0]
    month = date_parts[1]

    directory_path = File.join(
      @dropbox_folder,
      year,
      "#{year} - #{month} #{ENV['COMPANY_NAME']} Taxes",
      'invoices'
    )

    FileUtils.mkdir_p(directory_path)

    source_path = File.join(@email_attachments_folder, expense['filename'])
    destination_path = File.join(directory_path, expense['filename'])

    if File.exist?(source_path)
      FileUtils.mv(source_path, destination_path)
      puts "Moved #{expense['filename']} to #{directory_path}"
    else
      puts "Warning: Source file not found: #{source_path}"
    end
  end
end
