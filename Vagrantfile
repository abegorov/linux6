# -*- mode: ruby -*-
# vi: set ft=ruby :

# curl -O https://cloud.centos.org/centos/7/vagrant/x86_64/images/CentOS-7-x86_64-Vagrant-1804_02.VirtualBox.box
# vagrant box add CentOS-7-x86_64-Vagrant-1804_02.VirtualBox.box --name "centos/7/1804.02"

ENV["LC_ALL"] = "en_US.UTF-8"
vbox_info = %x(VBoxManage list systemproperties)
vbox_vms_dir = vbox_info.match('Default machine folder:\s+(.+)')[1]

MACHINES = {
  :'lvm-abegorov' => {
    :box => 'centos/7/1804.02',
    :cpus => 2,
    :memory => 512,
    :disks => {
      :sata1 => '10240',
      :sata2 => '2048',
      :sata3 => '1024',
      :sata4 => '1024'
    },
    :script => 'provision.sh'
  }
}

Vagrant.configure('2') do |config|
  MACHINES.each do |host_name, host_config|
    config.vm.define host_name do |host|
      host.vm.box = host_config[:box]
      host.vm.host_name = host_name.to_s

      host.vm.provider :virtualbox do |vb|
        vb.name = host_name.to_s
        vb.cpus = host_config[:cpus]
        vb.memory = host_config[:memory]

        vm_dir = "#{vbox_vms_dir}/#{host_name.to_s}"
        unless Dir.exist?(vm_dir)
          vb.customize ['storagectl', :id, '--name', 'SATA', '--add', 'sata']
        end
        host_config[:disks].each_with_index do |disk, index|
          disk_file = "#{vm_dir}/#{disk[0].to_s}.vdi"
          unless File.exist?(disk_file)
            vb.customize [
              'createmedium', 'disk',
              '--filename', disk_file,
              '--format', 'VDI',
              '--variant', 'Standard',
              '--size', disk[1]
            ]
            vb.customize [
              'storageattach', :id,
              '--storagectl', 'SATA',
              '--port', index,
              '--device', 0,
              '--type', 'hdd',
              '--medium', disk_file
            ]
          end
        end
      end

      host.vm.provision :shell do |shell|
        shell.path = host_config[:script]
        shell.privileged = false
      end
    end
  end
end
