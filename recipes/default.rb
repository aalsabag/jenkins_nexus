#
# Cookbook:: jenkins_nexus
# Recipe:: default
#
# Copyright:: 2018, The Authors, All Rights Reserved.


directory "/tmp/AhmedAlsabag" do 
	action :create
end

include_recipe "jenkins_nexus::nexus"
include_recipe "jenkins_nexus::jenkins"


