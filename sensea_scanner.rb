require 'ferrum'

require 'logger'
require 'json'
require 'date'
require 'time'
require 'digest'

class SenseaScanner
  SWEDISH_URL = "https://sensea.as.me/?appointmentType=12789431"
  DEEP_TISSUE_URL = "https://sensea.as.me/?appointmentType=12789613"
  COUPLES_URL = "https://sensea.as.me/?appointmentType=13182311"
  TIMEOUT = 120
  DAYS_TO_SCAN = (ENV['DAYS_TO_SCAN'] || 30).to_i
  
  def initialize
    @logger = Logger.new(STDERR)
    @browser = Ferrum::Browser.new(
      headless: ENV['HEADLESS'] != 'false',
      timeout: TIMEOUT,
      process_timeout: TIMEOUT,
      window_size: [1280, 1024],
      js_errors: false,
      browser_options: {
        'user-agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'no-sandbox': nil,
        'disable-dev-shm-usage': nil,
        'disable-gpu': nil
      }
    )
    @results = {}
    @logger.info "SenseaScanner initialized. Timeout: #{TIMEOUT}s. Browser launching..."
  end

  def scan
    @logger.info "Starting scan process..."
    scan_type = ENV['SCAN_TYPE']
    @logger.info "Days to scan: #{DAYS_TO_SCAN}"
    @logger.info "Scan Type: #{scan_type || 'ALL (Default)'}"

    begin
      if scan_type == 'spapass'
        scan_spa_pass
      elsif scan_type == 'massage'
        scan_massages
      else
        # Default: Scan both
        scan_massages
        scan_spa_pass
      end

      # 3. Output JSON
      @logger.info "Scan complete. Generating JSON output..."
      
      # Add metadata
      @results['_meta'] = {
        generated_at: Time.now.iso8601
      }
      
      json_output = JSON.pretty_generate(@results)
      puts json_output
      
      # Save to file for frontend
    File.write('www/appointments.json', json_output)
    
    # Generate and save MD5 hash
    md5 = Digest::MD5.hexdigest(json_output)
    File.write('www/appointments.md5', md5)
    
    @logger.info "JSON output saved to www/appointments.json (MD5: #{md5})"

    rescue => e
      @logger.error "CRITICAL ERROR during scan: #{e.message}"
      @logger.error e.backtrace.join("\n")
    ensure
      @logger.info "Closing browser..."
      @browser.quit
    end
  end
  
  def scan_massages
    massage_type = ENV['MASSAGE_TYPE']
    @logger.info "Massage Type: #{massage_type || 'ALL (Default)'}"
    
    if massage_type == 'swedish'
      scan_massage_staff(SWEDISH_URL, "Swedish")
    elsif massage_type == 'deep_tissue'
      scan_massage_staff(DEEP_TISSUE_URL, "Deep Tissue")
    elsif massage_type == 'couples'
      scan_massage_staff(COUPLES_URL, "Couples")
    else
      scan_massage_staff(SWEDISH_URL, "Swedish")
      scan_massage_staff(DEEP_TISSUE_URL, "Deep Tissue")
      scan_massage_staff(COUPLES_URL, "Couples")
    end
  end

  def scan_spa_pass
    url = "https://sensea.as.me/?appointmentType=15360506"
    # Use the category URL as requested
    url = "https://sensea.as.me/schedule/1e0cc157/category/Spa%2520pass"
    @logger.info "Navigating to Spa Pass category page: #{url}"
    @browser.go_to(url)
    
    # Wait for page to load - Optimized
    # Instead of sleep 2, wait for the button we need
    
    # Find and click the "Select" button specifically for Spa Pass
    # The structure is usually a container with the name and the button
    begin
      # XPath to find the button relative to the "Spa pass" text
      # We look for a container (li) that has a div with exact text "Spa Pass" and a "Select" button
      # Using normalize-space to handle potential whitespace
      xpath = "//li[contains(@class, 'select-item') and .//div[contains(@class, 'appointment-type-name') and normalize-space(text())='Spa Pass']]//button[contains(., 'Select')]"
      
      # Wait for the button to appear (manual polling since at_xpath doesn't support timeout)
      btn = nil
      50.times do
        btn = @browser.at_xpath(xpath)
        break if btn
        sleep 0.1
      end

      
      if btn
        @logger.info "Found 'Select' button for Spa Pass. Clicking..."
        btn.click # Try native click first
      else
        @logger.error "Could not find 'Select' button specifically for Spa Pass."
        # Fallback to dumping HTML to see why
        File.write("debug_spa_pass_select_fail.html", @browser.body)
        return
      end
    rescue => e
      @logger.error "Error clicking 'Select' button: #{e.message}"
      return
    end
    
    # Wait for calendar to appear
    begin
      # Removed wait_for_idle as it causes unnecessary delays
      # @browser.network.wait_for_idle
      # Wait up to 5 seconds for calendar header, check every 0.1s
      found = false
      50.times do
        if @browser.at_xpath("//button[contains(@class, 'react-calendar__navigation__label')]")
          found = true
          break
        end
        sleep 0.1
      end
      
      if found
         @logger.info "Calendar loaded successfully."
      else
         @logger.warn "Calendar not detected immediately. Waiting an extra 2 seconds..."
         sleep 2
         @browser.screenshot(path: "debug_calendar_fail.png")
         File.write("debug_calendar_fail.html", @browser.body)
         @logger.info "Saved debug screenshot to debug_calendar_fail.png and HTML to debug_calendar_fail.html"
      end
    rescue
      sleep 1
    end

    # Check calendar
    available_slots = []
    
    # Check current month
    @logger.info "Scanning current month view..."
    available_slots.concat(scrape_month)
    
    # Check next month
    next_btn = @browser.at_xpath("//button[contains(@class, 'react-calendar__navigation__next-button')]")
    if next_btn
      @logger.info "Clicking 'Next Month'..."
      next_btn.click
      sleep 0.5 
      @logger.info "Scanning next month view..."
      available_slots.concat(scrape_month)
    else
      @logger.info "No 'Next Month' button found."
    end
    
    # Filter for next N days
    cutoff = Date.today + DAYS_TO_SCAN
    filtered_slots = available_slots.select do |slot|
      begin
        Date.parse(slot[:date]) <= cutoff 
      rescue
        false
      end
    end
    
    @results["Spa Pass"] = {
      image_url: nil, 
      description: "Access to the Nordic Spa facilities.",
      booking_url: url,
      slots: filtered_slots.map { |s| [s[:date], s[:time], s[:spots]] }
    }
    
    if filtered_slots.any?
      @logger.info "SUCCESS: Found #{filtered_slots.count} slots for Spa Pass."
    else
      @logger.info "No availability found for Spa Pass."
    end
  end

  def scan_massage_staff(url, type_label)
    # 1. Discover Staff
    @logger.info "Navigating to #{type_label} booking page: #{url}"
    @browser.go_to(url)
    
    # Wait for staff list to load
    sleep 3
    
    # Scroll to ensure all elements are loaded
    @browser.execute("window.scrollTo(0, document.body.scrollHeight)")
    sleep 2
    
    # Extract Appointment Type ID from URL
    appt_type_id = url.match(/appointmentType=(\d+)/)[1].to_i
    
    # Get Business Data
    business_data = @browser.evaluate("window.BUSINESS")
    unless business_data
      @logger.error "Could not find window.BUSINESS object. Aborting scan for #{type_label}."
      return
    end
    
    # Find the appointment type to get valid calendar IDs
    appt_type = nil
    business_data['appointmentTypes'].each do |category, types|
      found = types.find { |t| t['id'] == appt_type_id }
      if found
        appt_type = found
        break
      end
    end
    
    unless appt_type
      @logger.error "Could not find appointment type #{appt_type_id} in business data."
      return
    end
    
    valid_calendar_ids = appt_type['calendarIDs']
    @logger.info "Found #{valid_calendar_ids.count} valid calendars for #{type_label}."
    
    # Flatten all calendars from all locations
    all_calendars = []
    business_data['calendars'].each do |location, calendars|
      all_calendars.concat(calendars)
    end
    
    staff_members = []
    
    valid_calendar_ids.each_with_index do |cal_id, index|
      staff_data = all_calendars.find { |c| c['id'] == cal_id }
      next unless staff_data
      
      name = staff_data['name']
      
      # Filter by TARGET_STAFF if set
      if ENV['TARGET_STAFF']
        targets = ENV['TARGET_STAFF'].split(',').map(&:strip).map(&:downcase)
        unless targets.any? { |t| name.downcase.include?(t) }
          @logger.info "Skipping #{name} (not in TARGET_STAFF)..."
          next
        end
      end
      
      # Use custom icons if applicable
      image_url = staff_data['thumbnail']
      if image_url && image_url.start_with?("//")
        image_url = "https:#{image_url}"
      end

      display_name = "#{name} (#{type_label})"
      booking_url = "#{url}&calendarID=#{cal_id}"
      
      @logger.info "Discovered staff: #{display_name}"
      
      staff_members << { 
        name: display_name, 
        original_name: name, 
        index: index, # Index is less relevant now but keeping for compatibility
        image_url: image_url, 
        description: staff_data['description'],
        booking_url: booking_url
      }
    end
    
    @logger.info "Total staff to scan: #{staff_members.count}"

    # 2. Iterate and Scan
    staff_members.each_with_index do |staff, i|
      @logger.info "Processing staff #{i + 1}/#{staff_members.count}: #{staff[:name]}"
      scan_staff(staff, url)
    end
  end
  


  def scan_staff(staff, url)
    @logger.info "--- Scanning #{staff[:name]} ---"
    
    # Navigate directly to the staff's booking URL
    if staff[:booking_url]
      @logger.info "Navigating directly to booking URL for #{staff[:name]}..."
      @browser.go_to(staff[:booking_url])
    else
      # Fallback to clicking button (legacy path)
      @logger.info "Navigating back to main page..."
      @browser.go_to(url)
      
      @logger.warn "No booking URL for #{staff[:name]}. Trying button click..."
      buttons = @browser.xpath("//button[contains(translate(., 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), 'select')] | //label[contains(translate(., 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), 'select')] | //div[contains(@class, 'btn') and contains(., 'Select')]")
      btn = buttons[staff[:index]]
      if btn
        @browser.execute("arguments[0].click()", btn)
      else
        @logger.error "Could not find button for #{staff[:name]}"
        return
      end
    end
      
    # Wait for calendar to appear - Optimized
    # Look for the month label or navigation
    begin
      # Removed wait_for_idle as it causes unnecessary delays on pages with background polling
      # @browser.network.wait_for_idle 
      
      # Wait up to 5 seconds for calendar header, check every 0.1s
      found = false
      50.times do
        if @browser.at_xpath("//button[contains(@class, 'react-calendar__navigation__label')]")
          found = true
          break
        end
        sleep 0.1
      end
      
      if found
         @logger.info "Calendar loaded successfully."
      else
         @logger.warn "Calendar not detected immediately. Waiting an extra 2 seconds..."
         sleep 2
      end
    rescue
      sleep 1
    end
    
    # Check calendar
    available_slots = []
    
    # Check current month
    @logger.info "Scanning current month view..."
    available_slots.concat(scrape_month)
    
    # Check next month
    next_btn = @browser.at_xpath("//button[contains(@class, 'react-calendar__navigation__next-button')]")
    if next_btn
      @logger.info "Clicking 'Next Month'..."
      next_btn.click
      # Optimized wait for next month
      begin
        @browser.network.wait_for_idle(timeout: 2)
      rescue
        sleep 1
      end
      @logger.info "Scanning next month view..."
      available_slots.concat(scrape_month)
    else
      @logger.info "No 'Next Month' button found (possibly end of available schedule)."
    end
    
    # Filter for next N days
    cutoff = Date.today + DAYS_TO_SCAN
    filtered_slots = available_slots.select do |slot|
      begin
        # Parse date carefully. Acuity aria-label is usually "Month Day, Year" e.g. "November 30, 2025"
        # Or it might be YYYY-MM-DD if we constructed it manually
        parsed_date = Date.parse(slot[:date])
        is_valid = parsed_date <= cutoff
        # @logger.info "  Filter: #{slot[:date]} (#{parsed_date}) <= #{cutoff} ? #{is_valid}"
        is_valid
      rescue => e
        @logger.warn "Failed to parse date: #{slot[:date]}"
        false
      end
    end
    
    # Store result with image, and description
    @results[staff[:name]] = {
      image_url: staff[:image_url],
      description: staff[:description],
      booking_url: staff[:booking_url],
      slots: filtered_slots.map { |s| [s[:date], s[:time], s[:spots]] }
    }
    
    if filtered_slots.any?
      @logger.info "SUCCESS: Found #{filtered_slots.count} slots for #{staff[:name]} in the next #{DAYS_TO_SCAN} days."
    else
      @logger.info "No availability found for #{staff[:name]} in the next #{DAYS_TO_SCAN} days."
    end
  end

  def scrape_month
    slots = []
    
    # Determine current view month/year from header
    header = @browser.at_xpath("//button[contains(@class, 'react-calendar__navigation__label')]")
    if header
      header_text = header.text.strip # e.g., "November 2025"
      begin
        header_date = Date.parse("1 #{header_text}")
        year = header_date.year
        month = header_date.month
        @logger.info "Identified calendar view: #{header_text}"
      rescue => e
        @logger.warn "Failed to parse calendar header: #{header_text}"
        year = Date.today.year
        month = Date.today.month
      end
    else
      @logger.warn "Could not find calendar header. Assuming current month."
      @browser.screenshot(path: "debug_missing_header.png")
      File.write("debug_missing_header.html", @browser.body)
      year = Date.today.year
      month = Date.today.month
    end
    
    # Find all active days
    days = @browser.xpath("//button[contains(@class, 'react-calendar__tile') and not(@disabled)]")
    @logger.info "Found #{days.count} active days in this month view."
    
    days.count.times do |i|
      # Re-find the day button to avoid stale element
      day_btns = @browser.xpath("//button[contains(@class, 'react-calendar__tile') and not(@disabled)]")
      day_btn = day_btns[i]
      next unless day_btn
      
      date_str = day_btn.attribute('aria-label')
      if date_str.nil? || date_str.empty?
        # Fallback: construct date from text (day number) and context
        day_num = day_btn.text.to_i
        if day_num > 0
          date_str = Date.new(year, month, day_num).strftime("%B %d, %Y")
        else
          date_str = day_btn.text # Should not happen but fallback
        end
      end
      
      # Click to reveal times
      day_btn.click
      
      # Optimized wait: Wait for network idle instead of hard sleep
      begin
        @browser.network.wait_for_idle(timeout: 1)
      rescue
        sleep 0.1 # Fallback if idle wait times out or fails
      end 
      
      # Scrape times
      # Look for inputs with name='time' or labels, OR p tags with AM/PM (dynamic classes)
      # Added button tag for Spa Pass which uses <button class="time-selection">
      times = @browser.xpath("//input[@name='time'] | //label[contains(@class, 'time-selection')] | //div[contains(@class, 'time-selection')] | //button[contains(@class, 'time-selection')]")
      
      # If no inputs/labels, try finding p tags with time format
      if times.empty?
        times = @browser.xpath("//p").select { |p| p.text.match?(/\d{1,2}:\d{2}\s*(AM|PM)/i) }
      end
      
      @logger.info "  -> #{date_str}: Found #{times.count} slots"
      
      times.each do |t|
        full_text = t.text.strip
        time_str = full_text
        
        # If input, get value
        if t.tag_name == 'input'
           time_str = t.attribute('value')
        end
        
        # Clean up time string (sometimes it has "Select 10:00 AM")
        time_str = time_str.gsub(/Select/i, '').strip
        
        # Extract spots left if present
        # Example: "10:00 AM 1 spot left" or "1:20 PM 7 spots left"
        spots_left = nil
        if full_text.match?(/(\d+)\s*spots?\s*left/i)
          spots_left = full_text.match(/(\d+)\s*spots?\s*left/i)[1].to_i
        end
        
        # Only add if it looks like a time
        if time_str.match?(/\d{1,2}:\d{2}/)
           # Clean time_str to just the time part for consistency
           clean_time = time_str.match(/(\d{1,2}:\d{2}\s*(?:AM|PM)?)/i)[1]
           slots << { date: date_str, time: clean_time, spots: spots_left }
           if spots_left
             @logger.info "     -> Added slot: #{clean_time} (#{spots_left} spots left)"
           else
             @logger.info "     -> Added slot: #{clean_time}"
           end
        end
      end
    end
    
    slots
  end
end

if __FILE__ == $0
  SenseaScanner.new.scan
end
