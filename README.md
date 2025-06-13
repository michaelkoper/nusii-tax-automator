# Nusii Tax Automation

Automated tax processing system for Nusii Proposals S.L. that handles expense tracking, invoice processing, and integration with Stripe, Quaderno, and other financial services.

## Features

- **Stripe Report Downloads**: Automatically download balance and payout reports in multiple currencies
- **PDF Invoice Processing**: Extract data from PDF invoices using OpenAI's GPT-4
- **Quaderno Integration**: Upload processed expenses to Quaderno with proper categorization
- **Automated Filing**: Organize processed invoices into monthly tax folders

## Prerequisites

- Ruby 3.0 or higher
- Bundler
- API keys for:
  - Stripe
  - OpenAI
  - Quaderno

## Installation

1. Clone this repository:
```bash
git clone [repository-url]
cd code
```

2. Install dependencies:
```bash
bundle install
```

3. Copy the environment variables template:
```bash
cp .env.example .env
```

4. Edit `.env` and add your API keys and configuration:
```bash
# Company Configuration
COMPANY_NAME=YourCompanyName
# Comma-separated list of currencies for Stripe reports (e.g., usd,eur or usd,eur,gbp)
STRIPE_CURRENCIES=usd

# Required API keys
STRIPE_API_KEY=your_stripe_api_key
OPENAI_API_KEY=your_openai_api_key
QUADERNO_API_KEY=your_quaderno_api_key
QUADERNO_API_URL=https://your_account.quadernoapp.com/api/

# Paths
DROPBOX_FOLDER=/path/to/your/dropbox/taxes/folder
EMAIL_ATTACHMENTS_FOLDER=/path/to/your/email/attachments/folder
CODE_ROOT=/path/to/this/code/directory
```

## Usage

Run the main tax processor:

```bash
ruby taxes.rb
```

The interactive menu provides these options:

1. **Download Stripe reports** - Downloads monthly reports for all configured currencies
2. **Process PDF invoices** - Extracts data from PDFs in your Email Attachments folder
3. **Show expenses JSON file** - Display the processed expense data
4. **Upload to Quaderno** - Uploads processed invoices to Quaderno
5. **Compress tax folder** - Creates a zip file of the monthly tax folder
6. **Exit** - Quit the application

### Typical Workflow

1. Place PDF invoices in your Email Attachments folder
2. Run `ruby taxes.rb`
3. Select "Complete tax workflow"
4. Choose the month to process
5. The system will:
   - Download Stripe reports to the appropriate monthly folder
   - Process all PDF invoices and extract expense data
   - Upload expenses to Quaderno with proper categorization
   - Move processed PDFs to the monthly tax folder

## File Organization

Processed files are organized as follows:
```
Dropbox/Taxes/
├── 2024/
│   ├── 2024-01 CompanyName Taxes/
│   │   ├── invoices/          # Processed PDF invoices
│   │   ├── Balance_summary_*.csv
│   │   └── Payouts_summary_*.csv
│   └── 2024-02 CompanyName Taxes/
│       └── ...
```

## Configuration

### Environment Variables

- **COMPANY_NAME**: Your company name (used in zip file naming)
- **STRIPE_CURRENCIES**: Comma-separated list of currencies to download Stripe reports for (e.g., `usd`, `usd,eur`, `usd,eur,gbp`)

### Vendor Categories

The system automatically categorizes invoices from known vendors using the `config/category_mappings.yml` file. This YAML configuration defines:
- Vendor names and their Quaderno contact IDs
- Item descriptions for each vendor
- Payment methods (credit_card, direct_debit, etc.)
- Mappings for vendor name variations

To add a new vendor, edit `config/category_mappings.yml` and add an entry under the `vendors` section.

## Temporary Files

The system uses a `temp/` directory for intermediate processing:
- `temp/expenses.json` - Extracted invoice data before uploading to Quaderno

## Troubleshooting

### PDF Processing Issues
- Ensure PDFs are readable and not password-protected
- Check that the OpenAI API key has sufficient credits
- Review `temp/expenses.json` for extraction results

### Quaderno Upload Errors
- Verify the Quaderno API key and URL are correct
- Check that vendor categories match those in `config/category_mappings.yml`
- Ensure the Quaderno contact IDs are valid

### Missing Dependencies
Run `bundle install` to ensure all gems are installed.

## Development

### Adding New Vendors

1. Edit `config/category_mappings.yml`
2. Add the vendor under the `vendors` section:
```yaml
vendors:
  new_vendor:
    contact_id: 12345678
    contact_full_name: "Vendor Name"
    item_description: "Service description"
    payment_method: "credit_card"
```

3. Update the AI prompt in `prompt.txt` to recognize the vendor in invoice processing

## Security Notes

- Never commit the `.env` file to version control
- Keep API keys secure and rotate them regularly
- The `.gitignore` file is configured to exclude sensitive data
