class HiveQueen
  SSH_BASTION = ENV['KSR_SSH_BASTION'] || 'ssh-bastion'
  SSH_PUBKEY  = ENV['KSR_SSH_PUBKEY']  || '~/.ssh/ksr_ed25519.pub'
  SSH_USER    = ENV['KSR_SSH_USER']    || 'ksr'

  def self.ec2_client
    @ec2_client ||= Aws::EC2::Client.new
  end

  def self.ec2_instance_connect_client
    @ec2_instance_connect_client ||= Aws::EC2InstanceConnect::Client.new(
      retry_limit:   5,
      retry_backoff: -> (c) { sleep(5) },
    )
  end

  def self.ec2_instance_connect(*private_dns)
    # Get EC2 instances from private DNS name
    instances = get_bastions + get_instances(*private_dns)

    # Collect EC2 Instance Connect request threads
    threads = instances.map { |i| Thread.new { instance_connect(i) } }

    # Execute EC2 Instance Connect request threads
    threads.each(&:join)
  end

  def self.ec2_instances(**params)
    logger.trace("ec2:DescribeInstances #{params.to_json}")
    ec2_client.describe_instances(**params).
      map(&:reservations).flatten.
      map(&:instances).flatten
  end

  def self.get_bastions
    # Get SSH bastion instance(s) from Name tag
    ec2_instances(filters: [
      { name: 'tag:Name', values: [SSH_BASTION] },
      { name: 'instance-state-name', values: %w[running] },
    ])
  end

  def self.get_instances(*private_dns)
    ec2_instances(filters: [
      { name: 'network-interface.private-dns-name', values: private_dns },
      { name: 'instance-state-name', values: %w[running] },
    ])
  end

  def self.instance_connect(instance)
    params = {
      availability_zone: instance.placement.availability_zone,
      instance_id:       instance.instance_id,
      instance_os_user:  SSH_USER,
      ssh_public_key:    ssh_public_key,
    }
    logger.trace("ec2-instance-connect:SendSSHPublicKey #{params.to_json}")
    ec2_instance_connect_client.send_ssh_public_key(**params)
  end

  def self.ssh_public_key
    @ssh_public_key ||= File.read(File.expand_path(SSH_PUBKEY))
  end
end
