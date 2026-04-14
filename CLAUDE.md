# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Ruby-based tax automation system that streamlines tax processing workflows. The system primarily handles downloading Stripe financial reports, organizing tax documents, and creating compressed archives for tax filing.

## Key Features

- **Stripe Report Downloads**: Automatically downloads balance and payout reports in multiple currencies
- **PDF Invoice Processing**: Processes PDF invoices using external tools
- **Quaderno Integration**: Uploads processed expenses to Quaderno tax management platform
- **Tax Folder Compression**: Creates zip archives of monthly tax folders for easy submission
- **Interactive CLI**: User-friendly command-line interface with menu-driven options

## Environment Variables

The following environment variables must be set:

- `COMPANY_NAME`: Company name used in file naming
- `STRIPE_API_KEY`: Stripe API key for downloading reports
- `STRIPE_CURRENCIES`: Comma-separated list of currencies (e.g., "usd,eur,gbp")
- `DROPBOX_FOLDER`: Path to the main tax storage directory
- `QUADERNO_API_KEY`: API key for Quaderno integration
- `QUADERNO_API_URL`: Quaderno API endpoint URL

## Directory Structure

Tax documents are organized hierarchically:
```
{DROPBOX_FOLDER}/
├── {year}/
│   ├── {year} - {month} {COMPANY_NAME} Taxes/
│   │   ├── Balance_summary_*.csv
│   │   ├── Payouts_summary_*.csv
│   │   ├── invoices/
│   │   └── {year}-{month} - {COMPANY_NAME}.zip
```

## Main Script: taxes.rb

The main entry point provides an interactive menu with these options:

1. Download Stripe reports for a selected month
2. Process PDF invoices from email attachments
3. Display processed expenses JSON
4. Upload expenses to Quaderno
5. Compress tax folder into a zip archive
6. Exit

## Development Notes

- The script uses TTY::Prompt for interactive CLI functionality
- All paths must be absolute, not relative
- Stripe reports are downloaded for all configured currencies
- Zip files are automatically overwritten if they exist
- The system will fail fast if required environment variables are missing

## Running the Application

```bash
bundle install  # Install dependencies
ruby taxes.rb   # Run the interactive tax processor
```

## CLI: bin/tax

The `bin/tax` command provides non-interactive access to Quaderno data. It outputs JSON to stdout and status messages to stderr. Use this for programmatic access (e.g., from Claude Code agents).

### Commands

```bash
bin/tax invoices [OPTIONS]          # List invoices (sales/income)
bin/tax invoices ID                 # Get a single invoice by ID
bin/tax expenses [OPTIONS]          # List expenses (purchases)
bin/tax expenses ID                 # Get a single expense by ID
bin/tax credits [OPTIONS]           # List credit notes
bin/tax credits ID                  # Get a single credit note by ID
bin/tax contacts [OPTIONS]          # List contacts from Quaderno
bin/tax contacts ID                 # Get a single contact by ID
bin/tax contacts create [OPTIONS]   # Create a new contact in Quaderno
bin/tax contacts local              # Show local contacts config (contacts.yml)
```

### Date Filtering

All list commands for invoices, expenses, and credits support date filtering:

```bash
bin/tax invoices --last-month
bin/tax invoices --last-quarter
bin/tax expenses --month 2026-03          # Specific month
bin/tax expenses --month 3                # Month 3 of current year
bin/tax expenses --quarter Q1-2026        # Specific quarter
bin/tax expenses --quarter Q1             # Q1 of current year
bin/tax invoices --from 2026-01-01 --to 2026-03-31  # Arbitrary range
bin/tax credits --year 2025 --quarter Q4  # Year + quarter
```

### Contact Operations

```bash
bin/tax contacts --query "OpenAI"         # Search contacts by name
bin/tax contacts create --full-name "Acme Corp" --tax-id "B12345" --country ES
bin/tax contacts local                    # Dump contacts.yml as JSON
```

### Modelo Verification Workflow

Use the `summary` command to generate pre-computed box values for all modelos:

```bash
bin/tax summary --quarter Q1-2026
```

This outputs a JSON structure with expected values for Modelos 111, 303, 349, and 369, including:
- IRPF withholding totals (111)
- VAT box values with domestic/EU/non-EU classification (303)
- EU operator listing with per-operator amounts (349)
- OSS country breakdown with arithmetic checks (369)
- Stripe fee totals extracted from PDF invoices (added to EU intra-community)

The summary automatically:
- Fetches invoices, expenses, and credit notes from Quaderno
- Converts all amounts to EUR using Quaderno exchange rates
- Classifies invoices as EU B2B / non-EU / EU B2C (OSS)
- Classifies expenses as domestic / EU intra-community / non-EU reverse charge
- Parses Stripe PDF invoices for the "Total fees in EUR" line
- Handles Greece GR→EL country code mapping for OSS

For raw data access, the individual commands are still available:

```bash
bin/tax invoices --quarter Q1-2026
bin/tax expenses --quarter Q1-2026
bin/tax credits --quarter Q1-2026
```

### Summary Configuration

The summary command uses these environment variables (see `.env.example`):

| Variable | Default | Purpose |
|----------|---------|---------|
| `COMPANY_COUNTRY` | `ES` | 2-letter country code for domestic classification |
| `VAT_RATE` | `21` | VAT rate for reverse charge self-assessment |
| `STRIPE_VAT_ID` | — | Stripe's EU VAT ID for Modelo 349 operator entry |
| `STRIPE_INVOICE_PATH` | — | Override Stripe invoice glob pattern (uses `{year}`, `{month}` placeholders) |
| `DROPBOX_FOLDER` | — | Base path for tax documents (also used to find Stripe PDFs) |
| `COMPANY_NAME` | — | Used in default Stripe invoice folder path |