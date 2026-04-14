require 'date'

module DateHelper
  # Parse various date range formats into [from_date, to_date] as Date objects.
  #
  # Supports:
  #   parse_range(from: "2026-01-01", to: "2026-03-31")
  #   parse_range(month: "2026-03")  or  parse_range(month: "3")
  #   parse_range(quarter: "Q1-2026") or parse_range(quarter: "Q1")
  #   parse_range(last_month: true)
  #   parse_range(last_quarter: true)
  #   parse_range(year: 2025, quarter: "Q4")
  def self.parse_range(from: nil, to: nil, month: nil, quarter: nil, last_month: false, last_quarter: false, year: nil)
    today = Date.today

    if last_month
      d = today << 1
      return [Date.new(d.year, d.month, 1), Date.new(d.year, d.month, -1)]
    end

    if last_quarter
      current_q = (today.month - 1) / 3 # 0-based quarter index
      if current_q == 0
        q_year = today.year - 1
        q_num = 4
      else
        q_year = today.year
        q_num = current_q
      end
      start_month = (q_num - 1) * 3 + 1
      return [Date.new(q_year, start_month, 1), Date.new(q_year, start_month + 2, -1)]
    end

    if quarter
      match = quarter.to_s.match(/\AQ([1-4])(?:-(\d{4}))?\z/i)
      raise ArgumentError, "Invalid quarter format: #{quarter}. Use Q1, Q2, Q3, Q4 or Q1-2026" unless match

      q_num = match[1].to_i
      q_year = match[2]&.to_i || year || today.year
      start_month = (q_num - 1) * 3 + 1
      return [Date.new(q_year, start_month, 1), Date.new(q_year, start_month + 2, -1)]
    end

    if month
      if month.to_s.include?('-')
        parts = month.to_s.split('-')
        m_year = parts[0].to_i
        m_month = parts[1].to_i
      else
        m_year = year || today.year
        m_month = month.to_i
      end
      return [Date.new(m_year, m_month, 1), Date.new(m_year, m_month, -1)]
    end

    from_date = from ? Date.parse(from.to_s) : nil
    to_date = to ? Date.parse(to.to_s) : nil
    [from_date, to_date]
  end
end
