# Nusii Tax Automation

Automated tax processing system for Nusii Proposals S.L. that handles expense tracking, invoice processing, and integration with Stripe, Quaderno, and other financial services.

## Features

- **Stripe Report Downloads**: Automatically download balance and payout reports in multiple currencies
- **PDF Invoice Processing**: Extract data from PDF invoices using OpenAI's GPT-4
- **Quaderno Integration**: Upload processed expenses to Quaderno with proper categorization
- **Automated Filing**: Organize processed invoices into monthly tax folders
- **Quaderno CLI** (`bin/tax`): Non-interactive access to invoices, expenses, credits, and contacts with date filtering
- **Tax Summary**: Generate pre-computed box values for Spanish tax modelos (111, 303, 349, 369) with automatic EUR conversion and transaction classification

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
# 2-letter country code where the company is registered (default: ES)
COMPANY_COUNTRY=ES
# Standard VAT rate for reverse charge self-assessment (default: 21)
VAT_RATE=21

# Required API keys
STRIPE_API_KEY=your_stripe_api_key
OPENAI_API_KEY=your_openai_api_key
QUADERNO_API_KEY=your_quaderno_api_key
QUADERNO_API_URL=https://your_account.quadernoapp.com/api/

# Stripe modelo verification
# Stripe's EU VAT ID — used to add Stripe as an operator in Modelo 349
STRIPE_VAT_ID=IE3206488LH
# Optional: override Stripe invoice path pattern (uses {year} and {month} placeholders)
# STRIPE_INVOICE_PATH=/custom/path/{year}/{month}/Stripe*.pdf

# Paths
DROPBOX_FOLDER=/path/to/your/dropbox/taxes/folder
EMAIL_ATTACHMENTS_FOLDER=/path/to/your/email/attachments/folder
CODE_ROOT=/path/to/this/code/directory
```

## Usage

### Interactive Mode

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

### CLI: `bin/tax`

The `bin/tax` command provides non-interactive access to Quaderno data. It outputs JSON to stdout and status messages to stderr, making it suitable for programmatic access and scripting.

```bash
bin/tax invoices [OPTIONS]          # List invoices (sales/income)
bin/tax invoices ID                 # Get a single invoice by ID
bin/tax expenses [OPTIONS]          # List expenses (purchases)
bin/tax expenses ID                 # Get a single expense by ID
bin/tax credits [OPTIONS]           # List credit notes
bin/tax credits ID                  # Get a single credit note by ID
bin/tax contacts [OPTIONS]          # List contacts
bin/tax contacts ID                 # Get a single contact by ID
bin/tax contacts create [OPTIONS]   # Create a new contact
bin/tax contacts local              # Show local contacts config (contacts.yml)
bin/tax summary --quarter Q1-2026   # Generate modelo verification summary
```

#### Date Filtering

All list commands for invoices, expenses, and credits support date filtering:

```bash
bin/tax invoices --last-month
bin/tax invoices --last-quarter
bin/tax expenses --month 2026-03          # Specific month
bin/tax expenses --month 3                # Month 3 of current year
bin/tax expenses --quarter Q1-2026        # Specific quarter
bin/tax expenses --quarter Q1             # Q1 of current year
bin/tax invoices --from 2026-01-01 --to 2026-03-31  # Arbitrary range
```

#### Contact Operations

```bash
bin/tax contacts --query "OpenAI"         # Search contacts by name
bin/tax contacts create --full-name "Acme Corp" --tax-id "B12345" --country ES
bin/tax contacts local                    # Dump contacts.yml as JSON
```

#### Tax Summary (Modelo Verification)

The `summary` command generates pre-computed box values for Spanish tax modelos:

```bash
bin/tax summary --quarter Q1-2026
```

This outputs a JSON structure with expected values for Modelos 111, 303, 349, and 369, including:
- **Modelo 111**: IRPF withholding totals per contact
- **Modelo 303**: VAT box values with domestic/EU/non-EU classification
- **Modelo 349**: EU intra-community operator listing with per-operator amounts
- **Modelo 369**: OSS country breakdown with arithmetic checks

The summary automatically fetches invoices, expenses, and credit notes from Quaderno, converts all amounts to EUR, classifies transactions by region, and parses Stripe PDF invoices for fee totals.

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

- **COMPANY_NAME**: Your company name (used in zip file naming and Stripe invoice paths)
- **STRIPE_CURRENCIES**: Comma-separated list of currencies to download Stripe reports for (e.g., `usd`, `usd,eur`, `usd,eur,gbp`)
- **COMPANY_COUNTRY**: 2-letter country code where the company is registered (default: `ES`)
- **VAT_RATE**: Standard VAT rate for reverse charge self-assessment (default: `21`)
- **STRIPE_VAT_ID**: Stripe's EU VAT ID, used to include Stripe as an operator in Modelo 349
- **STRIPE_INVOICE_PATH**: Optional override for the Stripe invoice glob pattern (uses `{year}` and `{month}` placeholders)

### Contacts

The system automatically categorizes invoices from known vendors using the `config/contacts.yml` file. This YAML configuration defines:
- Vendor names and their Quaderno contact IDs
- Item descriptions for each vendor
- Payment methods (credit_card, direct_debit, etc.)
- Optional `identifiers` (hints for recognizing invoices when the brand only appears in the logo)
- Optional `rules` (vendor-specific parsing instructions for the LLM)

To add a new vendor, edit `config/contacts.yml` and add an entry under the `contacts` section. The full contact list is automatically injected into the AI prompt at runtime — there's no need to edit `prompt.txt` when adding a vendor.

### Prompt Template

`prompt.txt` is rendered with [Liquid](https://shopify.github.io/liquid/) before being sent to OpenAI. Two variables are available:

- `{{ text_to_parse }}` — the extracted text of the PDF invoice being processed
- `{{ contacts }}` — a bullet list built from `config/contacts.yml`, giving the LLM the full set of valid category keys, their vendor names, and any identifiers/rules

See `prompt.txt.example` for a starting template.

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
- Check that vendor categories match those in `config/contacts.yml`
- Ensure the Quaderno contact IDs are valid

### Missing Dependencies
Run `bundle install` to ensure all gems are installed.

## Development

### Adding New Vendors

1. Edit `config/contacts.yml`
2. Add the vendor under the `contacts` section:
```yaml
contacts:
  new_vendor:
    contact_id: 12345678
    contact_full_name: "Vendor Name"
    item_description: "Service description"
    payment_method: "credit_card"
    # Optional: hints for the LLM when the vendor name is not in the
    # extracted PDF text (e.g. it only appears in the logo).
    identifiers:
      - "footer 'Some Company | Suite 3A'"
      - "product names like 'widget-pro' or 'widget-basic'"
    # Optional: vendor-specific parsing rules that override the generic
    # logic (e.g. which field to use for the date or total).
    rules:
      - "The invoice date is the 'Sent on' date, not the billing period"
```

Vendors, identifiers, and rules are injected into the LLM prompt automatically at runtime — no need to edit `prompt.txt`.

## Security Notes

- Never commit the `.env` file to version control
- Keep API keys secure and rotate them regularly
- The `.gitignore` file is configured to exclude sensitive data
