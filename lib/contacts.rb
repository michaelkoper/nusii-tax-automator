require 'yaml'

module Contacts
  CONFIG_FILE = File.join(File.dirname(__FILE__), '..', 'config', 'contacts.yml')

  # Load contact details from the YAML configuration file.
  # Returns a frozen hash keyed by vendor symbol.
  def self.all
    @all ||= load_config
  end

  def self.load_config
    unless File.exist?(CONFIG_FILE)
      raise "Contacts configuration not found!\n" \
            "Please copy config/contacts.example.yml to config/contacts.yml\n" \
            "and update it with your actual Quaderno contact IDs."
    end

    config = YAML.load_file(CONFIG_FILE)

    contacts = {}
    config['contacts'].each do |key, details|
      contacts[key.to_sym] = {
        contact_id: details['contact_id'],
        contact_full_name: details['contact_full_name'],
        item_description: details['item_description'],
        payment_method: details['payment_method'],
        identifiers: Array(details['identifiers']),
        rules: Array(details['rules'])
      }
    end

    contacts.freeze
  end
end
