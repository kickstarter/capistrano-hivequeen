class HiveQueen
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
    # Get SSH public key contents
    ssh_public_key = File.read(File.expand_path('~/.ssh/ksr_ed25519.pub'))

    # Get SSH bastion instance(s) from Name tag
    ssh_params = { filters: [{ name: 'tag:Name', values: %w[ssh-bastion] }, {name: 'instance-state-name', values: %w[running]}] }
    logger.trace("ec2:DescribeInstances #{ssh_params.to_json}")
    bastions = ec2_client.describe_instances(**ssh_params).reservations.map(&:instances).flatten

    # Get EC2 instances from private DNS name
    ec2_params = { filters: [{ name: 'network-interface.private-dns-name', values: private_dns }, {name: 'instance-state-name', values: %w[running]}] }
    logger.trace("ec2:DescribeInstances #{ec2_params.to_json}")
    instances = ec2_client.describe_instances(**ec2_params).reservations.map(&:instances).flatten

    # Collect EC2 Instance Connect request threads
    threads = (bastions + instances).map do |instance|
      Thread.new do
        ec2ic_params = {
          availability_zone: instance.placement.availability_zone,
          instance_id:       instance.instance_id,
          instance_os_user:  'ksr',
          ssh_public_key:    ssh_public_key,
        }
        logger.trace("ec2-instance-connect:SendSSHPublicKey #{ec2ic_params.to_json}")
        ec2_instance_connect_client.send_ssh_public_key(**ec2ic_params)
      end
    end

    # Execute EC2 Instance Connect request threads
    threads.each(&:join)
  end
end
