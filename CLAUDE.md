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