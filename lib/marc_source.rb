class MarcSource < Marc
  
  # record_type mapping
  RECORD_TYPES = {
    :unspecified => 0,
    :collection => 1,
    :source => 2,
    :edition_content => 3,
    :libretto_source => 4,
    :libretto_edition_content => 5,
    :theoretica_source => 6,
    :theoretica_edition_content => 7,
    :edition => 8
  }
  
  RECORD_TYPE_ORDER = [
    :collection,
    :source,
    :libretto_source,
    :theoretica_source,
    :edition,
    :edition_content,
    :libretto_edition_content,
    :theoretica_edition_content,
    :unspecified
  ]

  def initialize(source = nil, rt = 0)
    super("source", source)
    @record_type = rt
  end
  
  def record_type
    @record_type
  end
  
  # Get the std_title and std_title_d values  
  def get_std_title  
    std_title = ""
    std_title_d = ""
    standard_title = nil
    scoring = nil
    extract = nil
    arr = nil
    
    # try to get the title (240)
    # Quartets
    node = first_occurance("240", "a")
    standard_title = node.content.truncate(50) if node && node.content
    standard_title.strip! if standard_title
    
    # try to get the description (240 m)
    # vl (2), vla, vlc
    node = first_occurance("240", "m")
    scoring = node.content.truncate(50) if node && node.content
    scoring.strip! if scoring
   
    node = first_occurance("240", "k")
    extract = node.content.truncate(50) if node && node.content
    extract.strip! if extract
    
    node = first_occurance("240", "o")
    arr = node.content.truncate(50) if node && node.content
    arr.strip! if arr
   
    node = first_occurance("383", "b")
    opus = node.content.truncate(50) if node && node.content
    opus.strip! if opus
   
    node = first_occurance("690", "a")
    cat_a = node.content.truncate(50) if node && node.content
    cat_a.strip! if cat_a
    
    node = first_occurance("690", "n")
    cat_n = node.content.truncate(50) if node && node.content
    cat_n.strip! if cat_n
   
    cat_no = "#{cat_a} #{cat_n}".strip
    cat_no = nil if cat_no.empty? # For the join only nil is skipped 
   
    if !standard_title
      if @record_type == RECORD_TYPES[:collection]
        standard_title = "[Collection]"
      end
    end
    
    title = (standard_title != nil || standard_title != "") ? standard_title : "[Without title]" ## if title is unset and it is not collection

    desc = [extract, arr, scoring, opus, cat_no].compact.join("; ")
    desc = nil if desc.empty?
    
    # use join so the "-" is not places if one of the two is missing
    std_title = [title, desc].compact.join(" - ")
    std_title_d = DictionaryOrder::normalize(std_title)

    [std_title, std_title_d]
  end
  
  # Get the composer and composer_d values
  def get_composer
    composer = ""
    composer_d = ""
    if node = first_occurance("100", "a")
      person = node.foreign_object
      composer = person.full_name
      composer_d = person.full_name_d
    end
    [composer, composer_d]
  end

  def get_siglum
    if node = first_occurance("852", "a")
      return node.content
    end
  end
    
  # Get the Library and shelfmarc for a MARC record
  def get_siglum_and_shelf_mark
    siglum = "" 
    ms_no = ""
    
    tags_852 = by_tags(["852"])    
    if tags_852.length > 1 # we have multiple copies
      tags_852.each do |tag|
				t = tag.fetch_first_by_tag("a")
				next if !t || !t.content
        a_tag = t.content
        siglum = siglum == "" ? "#{a_tag}" : "#{siglum}, #{a_tag}"
      end
      #siglum = "[multiple copies]"
      ms_no = "[multiple copies]"
          
    elsif tags_852.length == 1 # single copy
      if node = first_occurance("852", "a")
        siglum = node.foreign_object.siglum
        siglum = "" if !siglum
      end
      if node = first_occurance("852", "c")
        ms_no = node.content if node.content
      end
    end
    
    return [siglum.truncate(255), ms_no.truncate(255)]
  end
  
  # On RISM A/1 ms_no contains the OLD RISM ID, get it from 035
  def get_book_rism_id
    if node = first_occurance("035", "a")
      return node.content
    end
  end

  
  # For bibliographic records, set the ms_title and ms_title_d field fromMARC 245 or 246
  def get_source_title
    ms_title = "[unset]"  
    ms_title_field = (RISM::BASE == "in") ? "246" : "245" # one day the ms_title field (and std_title field) should be put in the environmnent.rb file
    if node = first_occurance(ms_title_field, "a")
      ms_title = node.content
    end

    ms_title_d = DictionaryOrder::normalize(ms_title)
   
    return [ms_title.truncate(255), ms_title_d.truncate(255)]
  end
  
  # Set miscallaneous values
  def get_miscellaneous_values

    language = "Unknown"
    date_from = nil
    date_to = nil

    if node = first_occurance("008")
      unless node.content.empty?
        language = LANGUAGES[marc_helper_get_008_language(node.content)] || "Unknown"
      end
    end
    
    if node = first_occurance("033", "a")
      if node && node.content
        date_from = marc_get_range(node.content, 0, 4) || nil
        date_to = marc_get_range(node.content, 4, 4) || nil
      end
    end

    # Force it to nil if 0, this used to work in the past
    date_from = nil if date_from.to_i == 0
    date_to = nil if date_to.to_i == 0
    
    return [language.truncate(16), date_from, date_to]

  end
  
  def reset_to_new
    #load_source false if !@loaded
    first_occurance("001").content = "__TEMP__"
    by_tags("774").each {|t| t.destroy_yourself}
  end

  def match_leader
    rt = RECORD_TYPES[:unspecified]
    
    leader = nil
    if first_occurance("000") && first_occurance("000").content
      leader = first_occurance("000").content
    else
      puts "No leader present"
      return nil
    end
    if leader.match(/......[dcp]c.............../)
      rt = RECORD_TYPES[:collection]
    elsif leader.match(/......pd.............../) # Mixed material, subunit, ex convolutum
      rt = RECORD_TYPES[:collection]
    elsif leader.match(/......d[dm].............../)
      rt = RECORD_TYPES[:source]
    elsif leader.match(/......c[dm].............../)
      rt = RECORD_TYPES[:edition_content]
    elsif leader.match(/......tm.............../)
      rt = RECORD_TYPES[:libretto_source]
    elsif leader.match(/......am.............../)
      rt = RECORD_TYPES[:libretto_edition_content]
    elsif leader.match(/......pm.............../) # Mixed material, item
      rt = RECORD_TYPES[:source]
    else
       puts "Unknown leader #{leader}"
    end
    
    return rt
  end
  
  def to_internal
    # convert leader to record_type
    rt = match_leader
    
    # Drop leader
    by_tags("000").each {|t| t.destroy_yourself}
     
    # Drop other unused tags
    by_tags("003").each {|t| t.destroy_yourself}
    by_tags("005").each {|t| t.destroy_yourself}
    by_tags("007").each {|t| t.destroy_yourself}
    by_tags("008").each {|t| t.destroy_yourself}
    
    # Move 130 to 240
    each_by_tag("130") do |t|

      node = t.deep_copy
      node.tag = "240"
      node.indicator = "10"
      node.sort_alphabetically
      root.children.insert(get_insert_position("240"), node)
      
      t.destroy_yourself
      
    end
    
    each_by_tag("240") do |t|
      t.each_by_tag("n") do |st|
        st.destroy_yourself if st
      end
    end
    
    # Drop $2pe in 031, see #194
    each_by_tag("031") do |t|
      st = t.fetch_first_by_tag("2")
      if st && st.content && st.content != "pe"
        puts "Unknown 031 $2 value: #{st.content}"
      end
      st.destroy_yourself if st
    end
    
    # Remove the $a tag
    a = by_tags("594")
    a.each do |t|
      t.each_by_tag("a") do |st|
        st.destroy_yourself if st
      end
      
      # it the 594 is then empty remove it
      if t.all_children.count == 0
        t.destroy_yourself
      end
    end
    
    each_by_tag("691") do |t|
      t.each_by_tag("c") do |st|
        st.destroy_yourself if st
      end
    end
    
    each_by_tag("774") do |t|
      t.each_by_tag("t") do |st|
        st.destroy_yourself if st
      end
    end
    
    ## BUSH FIX
    ## #350
    # remove 700 with DE-588a links
    # these are IDS that do not exist in muscat
    a = by_tags("700")
    a.each do |t|
      st = t.fetch_first_by_tag("0")
      if st && st.content
        if st.content.include?("DE-588a")
          $stderr.puts "#{get_id}: ".magenta + "Killing 700 tag: ".green + t.to_s.yellow
          t.destroy_yourself
        end
      end
    end
    
    ## BUSH FIX
    ## #350
    # Kill 852 with $a but empty $x
    a = by_tags("852")
    a.each do |t|
      st = t.fetch_first_by_tag("a")
      stx = t.fetch_first_by_tag("x")
      if st && st.content
        if stx && stx.content.empty?
          $stderr.puts "#{get_id}: ".magenta + "Killing 852 tag: ".green + t.to_s.yellow 
          t.destroy_yourself
        end
      end
    end
    
    if rt
      @record_type = rt
    end
  end
  
  def to_external(updated_at = nil, versions = nil)
    super(updated_at, versions)
    
    # See #176
    # Step 1, rmake leader
    # collection, if we have prints only (......cc...............) or not (......dc...............)
    # manuscript and print, if it is part of a collection (......[cd]d...............) or not (......[cd]m...............)

    base_leader = "00000nXX#a2200000#u#4500"

    if ((@record_type == RECORD_TYPES[:collection]) || (@record_type == RECORD_TYPES[:edition]))
      type = "cc"
      
      each_by_tag("774") do |t|
        w = t.fetch_first_by_tag("w")
        if w && w.content
          source = Source.find(w.content)
          type = "dc" if source.record_type != RECORD_TYPES[:edition_content]
        else
          raise "Empty $w in 774"
        end
      end
      
      leader = base_leader.gsub("XX", type)
    elsif @record_type == RECORD_TYPES[:source]
      type = "dm"
      type = "dd" if by_tags("773").count > 0
      leader = base_leader.gsub("XX", type)
    elsif @record_type == RECORD_TYPES[:edition_content]
      type = "cm"
      type = "cd" if by_tags("773").count > 0
      leader = base_leader.gsub("XX", type)
    elsif @record_type == RECORD_TYPES[:libretto_source]
      leader = base_leader.gsub("XX", "tm")
    elsif @record_type == RECORD_TYPES[:libretto_edition_content]
      leader = base_leader.gsub("XX", "am")
    elsif @record_type == RECORD_TYPES[:theoretica_source] # we cannot make the distinction between ms and print
      leader = base_leader.gsub("XX", "pm")
    else
      puts "Unknown record type #{@record_type}"
      leader = ""
    end
    
    new_leader = MarcNode.new("source", "000", leader, "")
    @root.children.insert(get_insert_position("000"), new_leader)

    # 240 to 130 when 100 is not present
    if by_tags("100").count == 0
      each_by_tag("240") do |t|
        node = t.deep_copy
        node.tag = "130"
        node.indicator = "0#"
        node.sort_alphabetically
        root.children.insert(get_insert_position("130"), node)
      
        t.destroy_yourself
      end
    end
    
    # Put back $2pe in 031, see #194
    each_by_tag("031") do |t|
      t.add_at(MarcNode.new("source", "2", "pe", nil), 0)
      t.sort_alphabetically
    end

    #340 Add a 594 with $a
    scorings = []
    each_by_tag("594") do |t|
      b = t.fetch_first_by_tag("b")
      c = t.fetch_first_by_tag("c")
      
      if b && b.content
        if c && c.content && c.content.to_i > 1
          scorings << "#{b.content} (#{c.content})"
        else
          scorings << b.content
        end
      end
      
    end
    
    if scorings.count > 0
      n594 = MarcNode.new(@model, "594", "", "##")
      n594.add_at(MarcNode.new(@model, "a", scorings.join(", "), nil), 0)
      root.children.insert(get_insert_position("594"), n594)
    end

    if versions
      versions.each do |v|
        author = v.whodunnit != nil ? "#{v.whodunnit}, " : ""
        entry = "#{author}#{v.created_at} (#{v.event})"
        n599 = MarcNode.new(@model, "599", "", nil)
        n599.add_at(MarcNode.new(@model, "a", entry, nil), 0)
        @root.add_at(n599, get_insert_position("599"))
      end
        
    end
		
  end
  
  def set_record_type(rt)
    @record_type = rt
  end
  
end
