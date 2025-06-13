require 'faraday'
require 'json'
require 'base64'
require 'fileutils'
require_relative 'category_mappings'

class QuadernoClient
  include CategoryMappings

  def initialize
    @api_key = ENV['QUADERNO_API_KEY']
    @api_url = ENV['QUADERNO_API_URL']
    @email_attachments_folder = ENV['EMAIL_ATTACHMENTS_FOLDER']
    @dropbox_folder = ENV['DROPBOX_FOLDER']
    @temp_dir = File.join(ENV['CODE_ROOT'], 'temp')

    @connection = Faraday.new(url: @api_url) do |faraday|
      faraday.request :json
      faraday.response :json
      faraday.request :authorization, :basic, @api_key, 'x'
      faraday.adapter Faraday.default_adapter
    end
  end

  def upload_expenses
    expenses_file = File.join(@temp_dir, 'expenses.json')

    unless File.exist?(expenses_file)
      puts 'No expenses.json file found. Run PDF processor first.'
      return
    end

    expenses = JSON.parse(File.read(expenses_file))

    expenses.each do |expense|
      category = expense['category'].to_sym
      details = CATEGORY_DETAILS[category] || {}

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

  private

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
