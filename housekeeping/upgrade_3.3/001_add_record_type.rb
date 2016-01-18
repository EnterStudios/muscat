require 'progress_bar'

pb = ProgressBar.new(Source.all.count)

Source.all.each do |sa|
  
  s = Source.find(sa.id)
  
  s.record_type = s.marc.to_internal
  
  marc = s.marc
  
  #204 Move 300 $b to 500
  marc.each_by_tag("300") do |t|
    t8 = t.fetch_first_by_tag("8")
    tb = t.fetch_first_by_tag("b")
    
    next if !(t8 && t8.content) || !(tb && tb.content)
    
    new_500 = MarcNode.new("source", "500", "", "##")
    new_500.add_at(MarcNode.new("source", "a", tb.content, nil), 0)
    new_500.add_at(MarcNode.new("source", "8", t8.content, nil), 1)
    new_500.sort_alphabetically

    marc.root.children.insert(marc.get_insert_position("500"), new_500)
    
    #adios
    t8.destroy_yourself
    tb.destroy_yourself
    
    ap marc
    
  end
  
	s.suppress_update_77x
	s.suppress_update_count
  s.suppress_reindex
  
  begin
    s.save
  rescue => e
    puts e.message
  end
  
  pb.increment!
  
end