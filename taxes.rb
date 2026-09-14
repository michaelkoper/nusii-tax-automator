require 'dotenv/load'
require 'tty-prompt'
require 'fileutils'
require 'active_support'
require 'active_support/core_ext/integer/time'
require 'open-uri'
require 'stripe'
require 'json'

# Load our custom libraries
require_relative 'lib/pdf_processor'
require_relative 'lib/quaderno_client'
require_relative 'lib/contacts'

# TODO: download Stripe Tax Invoice
# TODO: download bank statements and put them in the drop box folder
# TODO: read bank statements and mark expenses as paid in Quaderno
# TODO: try to download a PDF invoice somehow

class TaxProcessor
  def initialize
    @prompt = TTY::Prompt.new
    @dropbox_folder = ENV['DROPBOX_FOLDER']

    # Configure Stripe
    Stripe.api_key = ENV['STRIPE_API_KEY']

    # Initialize processors
    @pdf_processor = PdfProcessor.new
    @quaderno_client = QuadernoClient.new
  end

  def run
    puts 'Starting automatic taxes'

    # The month is chosen once at startup and reused by every action.
    # It can be changed later via the last menu item.
    @month = select_month

    loop do
      choice = @prompt.select("What would you like to do? (#{month_label})") do |menu|
        menu.choice 'Download Stripe reports', 1
        menu.choice 'Process PDF invoices from Email Attachments', 2
        menu.choice 'Show expenses JSON file', 3
        menu.choice 'Upload processed invoices to Quaderno', 4
        menu.choice 'Compress tax folder', 5
        menu.choice 'Open tax folder in EDITOR', 6
        menu.choice 'Open tax folder in Finder', 7
        menu.choice 'Exit', 8
        menu.choice 'Change month', 9
      end

      case choice
      when 1
        download_stripe_reports
      when 2
        process_pdf_invoices
      when 3
        show_expenses_json
      when 4
        upload_to_quaderno
      when 5
        compress_tax_folder
      when 6
        open_tax_folder_in_editor
      when 7
        open_tax_folder_in_finder
      when 8
        puts 'Bye!'
        break
      when 9
        @month = select_month
        puts "\n✓ Month set to #{month_label}"
      end
    end
  end

  private

  def select_month
    options = [
      ['Previous month', 1.month.ago],
      ['Current month', Time.current],
      ['Next month', 1.month.from_now],
      ['Two months ago', 2.months.ago]
    ]

    choices = options.each_with_object({}) do |(label, time), hash|
      hash["#{label} (#{time.strftime('%B %Y')})"] = time
    end

    @prompt.select('For what month do you want to do the taxes?', choices)
  end

  def month_label
    @month.strftime('%B %Y')
  end

  def get_directory_name(month)
    "#{@dropbox_folder}/#{month.year}/#{month.year} - #{month.strftime('%m')} #{ENV.fetch('COMPANY_NAME')} Taxes"
  end

  # Returns the tax folder for the selected month, or nil (after a warning) if it doesn't exist yet.
  def existing_tax_folder
    dir_name = get_directory_name(@month)
    return dir_name if File.directory?(dir_name)

    puts "\n❌ Directory #{dir_name} does not exist!"
    puts 'Please create the tax folder first by downloading Stripe reports.'
    @prompt.keypress("\nPress any key to continue...")
    nil
  end

  def download_stripe_reports
    month = @month
    dir_name = get_directory_name(month)

    if @prompt.yes?('Do you want to create a folder in Dropbox?')
      FileUtils.mkdir_p(dir_name)
      puts "Directory #{dir_name} is created"
    end

    return unless @prompt.yes?('Do you want to download all Stripe reports?')

    interval_start = month.beginning_of_month.to_i
    interval_end = month.end_of_month.change(hour: 12, min: 0, sec: 0).to_i

    currencies = ENV.fetch('STRIPE_CURRENCIES').split(',').map(&:strip)
    report_types = %w[balance.summary.1 balance_change_from_activity.summary.1 payouts.summary.1]

    currencies.each do |currency|
      report_types.each do |report_type|
        puts "Creating report with currency: #{currency} and report type: #{report_type}"

        report = Stripe::Reporting::ReportRun.create({
                                                       report_type: report_type,
                                                       parameters: {
                                                         interval_start: interval_start,
                                                         interval_end: interval_end,
                                                         currency: currency
                                                       }
                                                     })

        while report.status == 'pending'
          report = Stripe::Reporting::ReportRun.retrieve(report.id)
          puts "Refetching report #{report.id} #{report.status}"
          sleep 5 if report.status == 'pending'
        end

        puts "Created report #{report.id}"

        file_id = report.result.id
        file_link = Stripe::FileLink.create({
                                              file: file_id
                                            })

        file_name = "#{report_type.split('.')[0..1].join('_').capitalize}_#{currency.upcase}_#{Time.at(interval_start).strftime('%F')}_#{Time.at(interval_end).strftime('%F')}.csv"

        File.open("#{dir_name}/#{file_name}", 'wb') do |file|
          file << URI.open(file_link.url).read
        end

        puts "Created file #{file_name}"
        puts
      end
    end
  end

  def process_pdf_invoices
    puts "\nProcessing PDF invoices from Email Attachments folder..."
    expenses = @pdf_processor.process_all_pdfs

    if expenses.empty?
      puts 'No PDF invoices found to process.'
    else
      puts "\n✓ Processed #{expenses.length} invoices successfully!"
      puts 'Expenses saved to temp/expenses.json'
    end
  end

  def upload_to_quaderno
    puts "\nUploading processed invoices to Quaderno..."
    @quaderno_client.upload_expenses
    puts "\n✓ Upload complete!"
  end

  def show_expenses_json
    system('clear') || system('cls')

    expenses_file = 'temp/expenses.json'

    unless File.exist?(expenses_file)
      puts "\n❌ No expenses file found at #{expenses_file}"
      puts "\nRun 'Process PDF invoices' first to generate the expenses file."
      @prompt.keypress("\nPress any key to continue...")
      return
    end

    expenses = JSON.parse(File.read(expenses_file))

    if expenses.empty?
      puts "\n📋 Expenses file is empty"
      @prompt.keypress("\nPress any key to continue...")
      return
    end

    puts "\n📋 Expenses from #{expenses_file}:"
    puts '=' * 80

    expenses.each_with_index do |expense, index|
      puts "\n##{index + 1}"

      # Check if category is unknown (not in Contacts)
      is_unknown = !Contacts.all.key?(expense['category'].to_sym)

      expense.each do |key, value|
        formatted_key = key.to_s.gsub('_', ' ').capitalize

        if key == 'category' && is_unknown
          # Red color for unknown categories
          puts "  #{formatted_key}: \e[31m#{value} (UNKNOWN)\e[0m"
        else
          puts "  #{formatted_key}: #{value}"
        end
      end
    end

    puts "\n" + '=' * 80
    puts "Total expenses: #{expenses.length}"

    # Show summary by category
    category_counts = expenses.group_by { |e| e['category'] }.transform_values(&:count)
    unknown_categories = category_counts.keys.select { |cat| !Contacts.all.key?(cat.to_sym) }

    if unknown_categories.any?
      puts "\n⚠️  Unknown categories found:"
      unknown_categories.each do |cat|
        puts "  - \e[31m#{cat}\e[0m (#{category_counts[cat]} expense#{category_counts[cat] > 1 ? 's' : ''})"
      end
    end

    @prompt.keypress("\nPress any key to continue...")
  end

  def compress_tax_folder
    month = @month
    dir_name = existing_tax_folder
    return unless dir_name

    # Generate zip filename with format: YYYY-MM - CompanyName.zip
    company_name = ENV.fetch('COMPANY_NAME')
    zip_filename = "#{month.year}-#{month.strftime('%m')} - #{company_name}.zip"
    zip_path = File.join(dir_name, zip_filename)

    # Delete existing zip file if it exists
    if File.exist?(zip_path)
      puts "\n🗑️  Deleting existing #{zip_filename}..."
      File.delete(zip_path)
    end

    puts "\n📦 Compressing tax folder..."
    puts "Source: #{dir_name}"
    puts "Destination: #{zip_path}"

    # Change to the tax folder directory and compress all contents
    Dir.chdir(dir_name) do
      system("zip -r \"#{zip_filename}\" .")
    end

    if File.exist?(zip_path)
      size_mb = (File.size(zip_path) / 1024.0 / 1024.0).round(2)
      puts "\n✓ Successfully created #{zip_filename} (#{size_mb} MB)"
    else
      puts "\n❌ Failed to create zip file"
    end

    @prompt.keypress("\nPress any key to continue...")
  end

  def open_tax_folder_in_editor
    dir_name = existing_tax_folder
    return unless dir_name

    editor = ENV['EDITOR'].to_s.strip
    if editor.empty?
      puts "\n❌ The EDITOR environment variable is not set."
      puts 'Set it in your shell or in .env (e.g. EDITOR=code) and try again.'
      @prompt.keypress("\nPress any key to continue...")
      return
    end

    puts "\n📝 Opening tax folder in #{editor}..."
    puts "Folder: #{dir_name}"

    if system("#{editor} \"#{dir_name}\"")
      puts "\n✓ Opened folder in #{editor}"
    else
      puts "\n❌ Failed to run '#{editor}'"
    end
    @prompt.keypress("\nPress any key to continue...")
  end

  def open_tax_folder_in_finder
    dir_name = existing_tax_folder
    return unless dir_name

    puts "\n📂 Opening tax folder in Finder..."
    puts "Folder: #{dir_name}"

    system("open \"#{dir_name}\"")

    puts "\n✓ Opened folder in Finder"
    @prompt.keypress("\nPress any key to continue...")
  end
end

# Run the application
if __FILE__ == $0
  processor = TaxProcessor.new
  processor.run
end
