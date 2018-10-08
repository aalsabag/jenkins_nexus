
##################################################
#Jenkins Install
remote_file "Jenkins Key Download" do
        source "https://pkg.jenkins.io/debian-stable/jenkins.io.key"
        path "/tmp/jenkins.io.key"
end

execute "Add Jenkins Key" do
	command "apt-key add /tmp/jenkins.io.key"
end

execute "Add Jenkins Repo" do
	command "echo 'deb https://pkg.jenkins.io/debian-stable binary/' | sudo tee -a /etc/apt/sources.list.d/jenkins.list; apt update"
end

apt_package "jenkins" do
	action :install
end

service "jenkins" do
	action [:restart, :enable]
end
##################################################

##################################################
#Jenkins Cli download from the newly started Jenkins instance.
#The cli will be used for the creation and updates of jobs as well as plugin downloads
remote_file "Download Jenkins CLI" do
	source "http://#{node[:ipaddress]}:8080/jnlpJars/jenkins-cli.jar"
	path "/var/lib/jenkins/jenkins-cli.jar"
	retries 10
	retry_delay 5
end
##################################################

##################################################
#This step will disable initial security configs
ruby_block "Modify config file to skip setup" do
	block do
	  sed = Chef::Util::FileEdit.new("/var/lib/jenkins/config.xml")
	  sed.search_file_replace_line(/<authorizationStrategy class.*\/>/, '<authorizationStrategy class="hudson.security.AuthorizationStrategy$Unsecured"/>')
	  sed.search_file_replace_line(/<securityRealm class.*\/>/,'<securityRealm class="hudson.security.SecurityRealm$None"/>')

	  sed.search_file_replace_line(/<authorizationStrategy class.*[^\/]>/, '<authorizationStrategy class="hudson.security.AuthorizationStrategy$Unsecured">')
	  sed.search_file_replace_line(/<securityRealm class.*[^\/]>/,'<securityRealm class="hudson.security.SecurityRealm$None">')

	  sed.write_file
	end
end
##################################################

##################################################
#The following steps within this block will disable the initial setup wizard
#Most of the setup is being done from within this recipe itself and the option to perform 
#other setup actions is still there
ruby_block "Add Java Args to Disable setup Wizard" do
	block do
	  sed = Chef::Util::FileEdit.new("/etc/default/jenkins")
	  sed.search_file_replace_line('JAVA_ARGS', 'JAVA_ARGS="-Djava.awt.headless=true -Djenkins.install.runSetupWizard=false"')
	  sed.write_file
	end
end

service "jenkins" do
	action [:restart, :enable]
end

execute "sleep for Jenkins" do
	command "sleep 8"
end

#Running a groovy script that sets the SetupWizard flag to complete
template "/var/lib/jenkins/disableSetup.groovy" do
	owner "jenkins"
	group "jenkins"
	source "disableSetup.groovy.erb"
end

execute "Disable setup Wizard With Groovy" do
	user "jenkins"
	command "cat /var/lib/jenkins/disableSetup.groovy | java -jar /var/lib/jenkins/jenkins-cli.jar -s http://localhost:8080/ groovy ="
end
##################################################

##################################################
#Using the Jenkins CLI, we are installing some common plugins
["GitHub","bitbucket", "pipeline-multibranch-defaults", "workflow-aggregator", "nexus-artifact-uploader","github-pullrequest","github-branch-source"].each do |package|
	execute "plugin" do
	    user "jenkins"
	    command "java -jar /var/lib/jenkins/jenkins-cli.jar -s http://localhost:8080/ install-plugin #{package}"
		retries 5
		retry_delay 5
	end
end

service "jenkins" do
	action [:restart, :enable]
end

execute "sleep for Jenkins" do
	command "sleep 20"
end
##################################################

##################################################
#Here we are creating an xml configuration of our spring-petclinic job
directory "/var/lib/jenkins/tmp" do
	owner "jenkins"
	group "jenkins"
	action :create
end

template "/var/lib/jenkins/tmp/config.xml" do
	owner "jenkins"
	group "jenkins"
	source "config.xml.erb"
end
#Nexus is usually up by this time now that I have allowed for more RAM
#But it's good to have checks just in case
bash "Wait for Nexus to Fully Come Up" do
	timeout 90
	code <<-EOH
	while [ ! curl http://ec2-52-91-80-194.compute-1.amazonaws.com:8081/internal/ping ];do  sleep 5; done
	sleep 5
	EOH
end
#This step INITIALLY creates the job with polling
#This was deliberately done so that we can actually get the first job to trigger automatically
#In later steps, the configuration is changed to a webhook
execute "Create Multibranch Pipeline" do
	user "jenkins"
	command "java -jar /var/lib/jenkins/jenkins-cli.jar -s http://localhost:8080/ create-job spring-petclinic < /var/lib/jenkins/tmp/config.xml"
end

service "jenkins" do
	action [:restart, :enable]
end

execute "sleep for Jenkins" do
	command "sleep 30"
end
##################################################


##################################################
#This step actually creates a webhook on github
#The challenge was that I never knew the public dns before hand
#So I decided to create it on the fly
remote_file "Webhook" do 
		source "https://github.com/ceejbot/jthooks/archive/master.zip"
		path "/tmp/master.zip"
end

execute "Unzip Master" do
		cwd "/tmp"
		command "unzip master.zip"
end

execute "NPM Install" do
		cwd "/tmp/jthooks-master"
		command "npm install"
end

bash "Webhook Creation" do
		cwd "/tmp/jthooks-master"
		code <<-EOH
		val=$(curl http://169.254.169.254/latest/meta-data/public-hostname)
		./hook-cli.js add aalsabag/spring-petclinic http://${val}:8080/github-webhook/ secretboy -a 62c8740880ad696002fbd14797ecd8c537d7af67
		EOH
end
##################################################

##################################################
#This switches the job configuration to REMOVE polling
template "/var/lib/jenkins/tmp/config.xml" do
	owner "jenkins"
	group "jenkins"
	source "config2.xml.erb"
end

#We do not update the job to remove polling UNTIL we have a successful initial build
bash "Create Multibranch Pipeline With Webhook" do
	user "jenkins"
	timeout 90
	code <<-EOH
	 while [ ! -d "/var/lib/jenkins/jobs/spring-petclinic/branches/master/builds/lastSuccessfulBuild" ];do  sleep 5; done
	 sleep 5
	 java -jar /var/lib/jenkins/jenkins-cli.jar -s http://localhost:8080/ update-job spring-petclinic < /var/lib/jenkins/tmp/config.xml
	 EOH
end
#Here we actually setup the job to use the webhook
ruby_block "Add Java Args to Enable Hook" do
	block do
	  sed = Chef::Util::FileEdit.new("/var/lib/jenkins/jobs/spring-petclinic/branches/master/config.xml")
	  sed.search_file_replace('<properties>', ' <properties><org.jenkinsci.plugins.workflow.job.properties.PipelineTriggersJobProperty>
      <triggers>
        <com.cloudbees.jenkins.GitHubPushTrigger plugin="github@1.29.2">
          <spec></spec>
        </com.cloudbees.jenkins.GitHubPushTrigger>
      </triggers>
    </org.jenkinsci.plugins.workflow.job.properties.PipelineTriggersJobProperty>')
	  sed.write_file
	end
end

service "jenkins" do
	action [:restart, :enable]
end

execute "sleep for Jenkins" do
	command "sleep 8"
end
##################################################