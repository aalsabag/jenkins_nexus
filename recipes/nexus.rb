##################################################
#JAVA Install
#Required for both Nexus and Jenkins
execute "Add Java Repo" do
	command "add-apt-repository ppa:webupd8team/java -y; apt update"
end

bash "Accept License Agreements" do
	code <<-EOH
		echo debconf shared/accepted-oracle-license-v1-1 select true | sudo debconf-set-selections
		echo debconf shared/accepted-oracle-license-v1-1 seen true | sudo debconf-set-selections
		apt install oracle-java8-installer -y
	EOH
end
##################################################

##################################################
#Creation of a nexus user as it is not recommended to run any apps as root
group "nexus" do
	action :create
end

user "nexus" do
	group "nexus"
	action :create
end
##################################################

##################################################
#Installation of packages
#All of these are to be used later during the installation
["maven","unzip","npm","nodejs-legacy"].each do |package2|
	apt_package package2 do
		action :install
	end
end
##################################################

##################################################
#Adds server authentication to nexus. This is the default admin user.
#This is necessary for the build step of our Jenkins job
ruby_block "Modify settings.xml to include nexus repo user/pass" do
	block do
	  sed = Chef::Util::FileEdit.new("/etc/maven/settings.xml")
	  sed.search_file_replace('<servers>', '<servers>
<server>
      <id>nexus</id>
      <username>admin</username>
      <password>admin123</password>
    </server>
')
	  sed.write_file
	end
end
#Nexus Installation directory
directory "/var/lib/nexus" do
	owner "nexus"
	group "nexus"
	action :create
end

remote_file "Download Nexus TGZ" do
	owner "nexus"
	group "nexus"
	source "https://download.sonatype.com/nexus/3/latest-unix.tar.gz"
	path "/var/lib/nexus/latest-unix.tar.gz"
end

execute "Unpack Nexus" do
	user "nexus"
	cwd "/var/lib/nexus"
	command "tar -xzvf latest-unix.tar.gz"
end

execute "Start Nexus" do
	user "nexus"
	command "/var/lib/nexus/nexus-*/bin/nexus start"
end
##################################################