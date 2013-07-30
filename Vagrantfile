
Vagrant.configure("2") do |config|
	PROJECT="anvils"
	RDIP="192.168.50.2"
	RUNDECK_YUM_REPO="https://bintray.com/rundeck/ci-snapshot-rpm/rpm"


	config.vm.box = "CentOS-6.3-x86_64-minimal"
	config.vm.box_url = "https://dl.dropbox.com/u/7225008/Vagrant/CentOS-6.3-x86_64-minimal.box"


	config.vm.define :rundeck do |rundeck|
		rundeck.vm.hostname = "rundeck.anvils.com"
		rundeck.vm.network :private_network, ip: "#{RDIP}"
		rundeck.vm.provision :shell, :path => "install-rundeck.sh", :args => "#{RDIP} #{RUNDECK_YUM_REPO}"
		rundeck.vm.provision :shell, :path => "install-httpd.sh"
		rundeck.vm.provision :shell, :path => "add-project.sh", :args => "#{PROJECT}"
	end
end
