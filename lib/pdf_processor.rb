require 'pdf-reader'
require 'ruby/openai'
require 'json'
require 'fileutils'

class PdfProcessor
  def initialize
    @openai_client = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])
    @email_attachments_folder = ENV['EMAIL_ATTACHMENTS_FOLDER']
    @temp_dir = File.join(ENV['CODE_ROOT'], 'temp')
  end

  def process_all_pdfs
    ensure_temp_directory

    expenses = []

    Dir.glob(File.join(@email_attachments_folder, '*.pdf')).each do |pdf_path|
      filename = File.basename(pdf_path)
      puts "Processing #{filename}"

      text = extract_text_from_pdf(pdf_path)
      processed_data = process_text_with_openai(text)

      if processed_data
        processed_data['filename'] = filename
        expenses << processed_data
      end
    end

    save_expenses_to_json(expenses)
    expenses
  end

  private

  def ensure_temp_directory
    FileUtils.mkdir_p(@temp_dir) unless Dir.exist?(@temp_dir)
  end

  def extract_text_from_pdf(pdf_path)
    text = ''

    PDF::Reader.open(pdf_path) do |reader|
      reader.pages.each do |page|
        text += page.text
      end
    end

    text
  rescue StandardError => e
    puts "Error extracting text from PDF #{pdf_path}: #{e.message}"
    ''
  end

  def process_text_with_openai(text)
    prompt = build_prompt(text)

    response = @openai_client.chat(
      parameters: {
        model: 'gpt-4',
        temperature: 0,
        messages: [
          {
            role: 'system',
            content: 'You are a utility which extracts accurate, structured JSON data from PDF invoices.'
          },
          {
            role: 'user',
            content: prompt
          }
        ]
      }
    )

    ai_response = response.dig('choices', 0, 'message', 'content')

    begin
      JSON.parse(ai_response)
    rescue JSON::ParserError => e
      puts 'Failed to decode JSON. Response was not in expected JSON format.'
      puts "AI Response: #{ai_response}"
      nil
    end
  rescue StandardError => e
    puts "An error occurred with OpenAI: #{e.message}"
    nil
  end

  def build_prompt(text)
    prompt_file_path = File.join(ENV['CODE_ROOT'] || File.dirname(__FILE__), 'prompt.txt')

    unless File.exist?(prompt_file_path)
      raise "Prompt file not found at #{prompt_file_path}. Please create it from prompt.txt.example"
    end

    prompt_template = File.read(prompt_file_path)
    prompt_template.gsub('{TEXT_TO_PARSE}', text)
  end

  def save_expenses_to_json(expenses)
    json_path = File.join(@temp_dir, 'expenses.json')

    File.open(json_path, 'w') do |file|
      file.write(JSON.pretty_generate(expenses))
    end

    puts "Saved #{expenses.length} expenses to #{json_path}"
  end
end
