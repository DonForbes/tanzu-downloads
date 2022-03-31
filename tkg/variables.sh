#
# Main variables that need to be set uniquely for each environment the scripts are run in.
#
export VMWUSER=<USERNAME>
export VMWPASS=<PASSWORD>

DOWNLOAD_LOCATION=/path/to/where/you/want/the/files


# Tested with TKG 1.5.2
CLI_VERSION=1.5.2

# The OVA files can be large and may not be necessary for your environment.  If set to false then they are not downloaded.
GET_OVA=false
# For airgapped environments you might want to download all the TKG images to transfer over.  If you have internet access then they are 
# not required.
GET_IMAGES=false
