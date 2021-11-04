"""LVD linux development on bareflank hypervisor"""

# Import the Portal object.
import geni.portal as portal
# Import the ProtoGENI library.
import geni.rspec.pg as pg

# Create a portal context.
pc = portal.Context()

# Create a Request object to start building the RSpec.
request = pc.makeRequestRSpec()
 
# Node node-0
node_0 = request.RawPC('node-0')
node_0.hardware_type = 'c220g2'
node_0.disk_image = 'urn:publicid:IDN+wisc.cloudlab.us+image+lvds-PG0:lvd-linux-4.8.4-ubuntu18-04'

# Node node-1
node_1 = request.RawPC('node-1')
node_1.hardware_type = 'c220g2'
node_1.disk_image = 'urn:publicid:IDN+wisc.cloudlab.us+image+lvds-PG0:lvd-linux-4.8.4-ubuntu18-04'

link1 = request.Link(members = [node_0, node_1])

# Install and execute a script that is contained in the repository.
#node.addService(pg.Execute(shell="sh", command="/local/repository/silly.sh"))

# Print the generated rspec
pc.printRequestRSpec(request)