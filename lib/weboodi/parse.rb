class WebOodi
	def relay page
		loop do
			form = page.form('relay') || page.forms.find {|f| f.form_node['id'] == 'shibboleth'}
			form = page.forms.first if !form && page.forms.size == 1 && page.forms.first.button_with(:value => /jatka oodiin/i)
			break if !form

			page.parser.encoding ||= 'iso-8859-1'
			page.encoding ||= 'iso-8859-1'

			$stderr.puts "Relay / Shibboleth page, submitting"
			page = form.dup.submit
		end
		page
	end

	def clean txt
		txt.to_s.gsub(/(\302\240|\s)+/m, ' ').strip
	end

	def parse target, table
		name = table.css('table.OK_OT td.OK_OT').first
		return if name.nil?
		name = clean name.text

		table.css('table.OK_OT table.OK_OT td.OK_OT').each do |td|
			tmp = td.css('input.submit2').first
			place = tmp ? clean(tmp['value']) : nil
			target << [name, clean(td.text), place]
		end
	end

	def initialize
		@m = WWW::Mechanize.new do |m|
			m.log = $logger
			m.history_added = lambda {|page| $stderr.puts " > Loaded #{page.uri}"}
			m.follow_meta_refresh = true
			m.cookie_jar.load($config_root + '/cookies', :cookiestxt) if File.exists? $config_root + '/cookies'
		end
		@courses = @menu = @front_page = nil
		@try_weblogin = true
		@try_oodilogin = true
	end

	def save_cookies
		@m.cookie_jar.save_as($config_root + '/cookies', :cookiestxt)
	end

	def login
		@m.follow_meta_refresh = false
		page = @front_page.frame('main') ? @front_page.frame('main').click : @front_page
		@m.follow_meta_refresh = true
		if @try_weblogin
			link = page.link_with(:text => /WebLogin/)
			page2 = link ? relay(link.click) : page
			page2 = page2.form_with(:name => 'query') do |login|
				login.user = self.class.username
				login.pass = self.class.password
			end.submit
			@front_page = relay page2
			return
		end

		if @try_oodilogin
			page2 = page.form_with(:name => 'login2') do |login|
				login.login = self.class.username
				login.pass = self.class.password
			end.submit
			@front_page = relay page2
		end
	end

	def logged?
		@menu && @menu.search('td.valikkonimi').text.strip.any?
	end

	def front_page
		return @front_page if @front_page

		@front_page = relay @m.get($options[:frontpage_url] || $options[:url])

		@front_page.link_with(:text => /weboodi/i) do |link|
			@front_page = relay(link.click) if link
		end

		@front_page
	end

	def menu
		return @menu if @menu

		@menu = front_page.frame('valikko') ? front_page.frame('valikko').click : nil
		if !logged?
			login
			@menu = front_page.frame('valikko').click if front_page.frame('valikko')
			raise "Login failed" unless logged?
		end
		$options[:frontpage_url] = @front_page.uri

		@menu
	end

	def courses
		return @courses if @courses

		$stderr.puts "Loading registrations"
		regs = menu.links.find {|l| l.text =~ /Ilmoittautumiset/}.click
		course_codes = regs.links.find_all {|l| l.href =~ /\/opintjakstied.jsp/}.map{|l| clean(l.text)}
		courses = regs.links.find_all {|l| l.href =~ /\/opettaptied.jsp/}

		@courses = {}
		courses.zip(course_codes).each do |c, code|
			course_name = clean(c.text)
			course = {:name => course_name, :lectures => [], :exercises => [], :exams => []}
			$stderr.puts "Loading course #{course_name}"
			page = c.click
			page.parser.css('table.kll').each do |table|
				case table.to_s
				when /<th [^>]*>\s*Luennot(\302\240|\s)*/
					parse course[:lectures], table
				when /<th [^>]*>\s*Harjoitukset(\302\240|\s)*/
					parse course[:exercises], table
				end
			end
			@courses[code] = course if course[:lectures].any? || course[:exercises].any?
		end
		@courses
	end

	def self.password
		return $options[:password] if $options[:password].to_s.any?
		$stderr.puts "Password:"
		old = `stty -g`.strip
		`stty -echo`
		$options[:password] = $stdin.gets.strip
	ensure
		`stty #{old}`
	end

	def self.username
		return $options[:user] if $options[:user].to_s.any?
		$stderr.puts "Username:"
		$options[:user] = $stdin.gets.strip
	end

	def self.courses
		if !$options[:sync] && File.exists?($config_root + '/cache')
			Marshal.load(File.open($config_root + '/cache'))
		else
			weboodi = WebOodi.new
			courses = weboodi.courses
			if courses
				weboodi.save_cookies
				File.open($config_root + '/cache', 'w') {|f| f.write Marshal.dump(courses)}
			end
			courses
		end
	end
end
