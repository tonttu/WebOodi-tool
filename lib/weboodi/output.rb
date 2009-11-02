# TODO: in !finnish
WDAYS = %w[su ma ti ke to pe la]

def each_date text
	parts = text.split
	return if parts.size != 3

	date, day, time = parts

	# 12.15-14.00
	istart, istop = time.split('-').map{|t| t.split('.').map{|y| y.to_i}}
	raise "Can't parse time #{time}" if istart.size != 2 || istop.size != 2

	wday = WDAYS.index day
	raise "Can't parse weekday #{day}" if wday.nil?

	#28.01.09 ke 15.00-18.00
	#08.09.-20.10.09 ti 08.15-10.00
	case date
	when /^(\d+)\.(\d+)\.(\d+)$/
		d, m, y = $1.to_i, $2.to_i, $3.to_i
		y += 2000 if y < 100
		dt = DateTime.new(y, m, d, istart[0], istart[1])
		dt2 = DateTime.new(y, m, d, istop[0], istop[1])
		raise "Corrupted date #{text}" if dt.wday != wday
		yield dt, dt2
	when /^(\d+)\.(\d+)\.-(\d+)\.(\d+)\.(\d+)$/
		d1, m1, d2, m2, y = $1.to_i, $2.to_i, $3.to_i, $4.to_i, $5.to_i
		y += 2000 if y < 100
		date1 = Date.new y, m1, d1
		date2 = Date.new y, m2, d2
		while date1 <= date2
			raise "Corrupted date #{text}" if date1.wday != wday
			yield DateTime.new(date1.year, date1.month, date1.day, istart[0], istart[1]), DateTime.new(date1.year, date1.month, date1.day, istop[0], istop[1])
			date1 += 7
		end
	else
		raise "Unknown date format #{date}"
	end
end

def time_to_s start, stop
	"%02d:%02d - %02d:%02d" % [start.hour, start.min, stop.hour, stop.min]
end

def print_items items
	items.each do |name, time, place|
		if $options[:verbose]
			each_date(time) do |start, stop|
				puts "      #{name}    #{WDAYS[start.wday]}  #{start.strftime '%d.%m.%Y'}  #{time_to_s start, stop}    #{place}"
			end
		else
			puts "      #{name}    #{time}    #{place}"
		end
	end
	puts
end

def print_courses courses
	courses.each do |code, course|
		puts "#{code} #{course[:name]}"
		if course[:lectures].any?
			puts "   Luennot"
			print_items course[:lectures]
		end

		if course[:exercises].any?
			puts "   Harjoitukset"
			print_items course[:exercises]
		end

		if course[:exams].any?
			puts "   Tentit"
			print_items course[:exams]
		end
		puts
	end
end

def collect_items items, after, before
	items.each do |name, time, place|
		each_date(time) do |start, stop|
			yield name, place, start, stop if stop >= after && start <= before
		end
	end
end

def print_next courses
	now = Time.now
	after = DateTime.civil now.year, now.month, now.day
	before = after + 2
	list = []
	courses.each do |code, course|
		for type in [:lectures, :exercises, :exams]
			collect_items(course[type], after, before) do |name, place, start, stop|
				list << [start, stop, code, course[:name], name, type, place]
			end
		end
	end
	typenames = {:lectures => 'Luento', :exercises => 'Laskarit', :exams => 'Tentti'}
	last = nil
	list.sort.each do |start, stop, code, course_name, name, type, place|
		if start.day != last
			last = start.day
			puts now.day == last ? "Tänään:" : "Huomenna:"
		end
		puts "  %-10s  %s   %13s %s %s (%s)" % [typenames[type], time_to_s(start, stop), code, course_name, name, place]
	end
end

def print_ical courses
	cal = Icalendar::Calendar.new
	courses.each do |course_code, course|
		course_name = course[:name]
		course[:lectures].each do |name, time, place|
			each_date(time) do |start, stop|
				e = cal.event
				e.dtstart start, { "TZID" => 'Europe/Helsinki' }
				e.dtend stop, { "TZID" => 'Europe/Helsinki' }
				e.summary = "#{course_name} #{name =~ /luen(to|not)/i ? '' : "luento "}#{name} (#{place})"
				e.description = "#{course_code} #{course_name}"
			end
		end
		course[:exercises].each do |name, time, place|
			each_date(time) do |start, stop|
				e = cal.event
				e.dtstart start, { "TZID" => 'Europe/Helsinki' }
				e.dtend stop, { "TZID" => 'Europe/Helsinki' }
				e.summary = "#{course_name} #{name =~ /har[kj]/i ? '' : "harkat "}#{name} (#{place})"
				e.description = "#{course_code} #{course_name}"
			end
		end
		course[:exams].each do |name, time, place|
			each_date(time) do |start, stop|
				e = cal.event
				e.dtstart start, { "TZID" => 'Europe/Helsinki' }
				e.dtend stop, { "TZID" => 'Europe/Helsinki' }
				e.summary = "Tentti #{course_name} #{name} (#{place})"
				e.description = "#{course_code} #{course_name}"
			end
		end
	end
	puts cal.to_ical
end
