require 'yaml'

module CategoryMappings
  CONFIG_FILE = File.join(File.dirname(__FILE__), '..', 'config', 'category_mappings.yml')
  
  # Load category details from YAML configuration file
  def self.load_config
    unless File.exist?(CONFIG_FILE)
      raise "Category mappings configuration not found!\n" \
            "Please copy config/category_mappings.example.yml to config/category_mappings.yml\n" \
            "and update it with your actual Quaderno contact IDs."
    end
    
    config = YAML.load_file(CONFIG_FILE)
    
    # Convert string keys to symbols and freeze the result
    vendors = {}
    config['vendors'].each do |key, details|
      vendors[key.to_sym] = {
        contact_id: details['contact_id'],
        contact_full_name: details['contact_full_name'],
        item_description: details['item_description'],
        payment_method: details['payment_method']
      }
    end
    
    vendors.freeze
  end
  
  # Load the configuration on module load
  CATEGORY_DETAILS = load_config
end