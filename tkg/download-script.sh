#!/bin/bash
# Setup authentication variables.
source ./variables.sh

# These variables are used to create subdirectories of the download location to put different files.
# TKG_DIR - downloads from vmware.com for tanzu command line, ISOs etc.
# TKG_IMAGES_DIR - All the container images used to power Tanzu Kubernetes Grid
# EXTENSIONS_IMAGE_DIR - Additional extensions to TKG that VMWare supports.  eg. Contour, Dex/Pinniped, harbor etc.
TKG_DIR="vmware_tanzu_kubernetes_grid"
TKG_IMAGES_DIR="images/tkg"
EXTENSIONS_IMAGE_DIR="images/tkg-extensions"

# if the TKG binaries download have already been done then the script will prompt to see if you want them downloaded again.
# setting the FORCE_DOWNLOAD to true will mean everything is downloaded again.
FORCE_DOWNLOAD=false

# The process of identifying all necessary images for TKG requires a number of activities.  The tmp directory is used to perform this processing
TMP_BASE_DIR=/tmp

# At time of writing only TKG 1.5.1 is supported....
CLI_VERSION=1.5.1


# Routines
validate()
{
	if [[ -z "${VMWUSER}" ]]; then
	   echo "You must export the VMWUSER env variable with a valid VMWare download user." 
	   exit 1
	fi
	if [[ -z "$VMWPASS}" ]]; then
		echo "You must export the VMWPASS env variable with a valid VMware download user password." 
	   exit 1
	fi
	if [[ -z "${DOWNLOAD_LOCATION}}" ]]; then
		echo "You must export the DOWNLOAD_LOCATION env variable with a valid local path to where downloads will be put." 
	   exit 1
	fi
	echo "Completed basic validation"
}

download_file()
{
        l_filename=$1
        l_download_dir=$2
        vmw-cli cp ${l_filename}
        mv ${l_filename} ${l_download_dir}
}
# End download_file

get-tkg-components ()
{
echo "getting tkg components."
mkdir -p ${DOWNLOAD_LOCATION}/${TKG_DIR}
TKG_FILES=$(vmw-cli ls ${TKG_DIR} | grep true | awk '{print $1}')
for filename in ${TKG_FILES}
do
        echo "Downloading [${filename}]"
        vmw-cli ls ${TKG_DIR} 2>&1 > /dev/null
        if ${FORCE_DOWNLOAD}
        then
                echo "force download"
                download_file "${filename}" "${DOWNLOAD_LOCATION}/${TKG_DIR}"
        else
                if test -f "${DOWNLOAD_LOCATION}/${TKG_DIR}/${filename}"; then
                        read -p "File [${filename}] already downloaded.  Do you want to download again? (y|n)" download
                        if [ "${download}" == "n" ]
                        then
                                echo "Skipping ${filename}"
                        else
                                download_file "${filename}" "${DOWNLOAD_LOCATION}/${TKG_DIR}"
                        fi
                else
                        echo "gettting as don't have yet."
                        download_file "${filename}" "${DOWNLOAD_LOCATION}/${TKG_DIR}"
                fi
        fi
done

}
get_image()
{
        l_repo=$(echo $1 | awk -F',' '{print $1}')
        l_name=$(echo $1 | awk -F',' '{print $2}')
        l_tag=$(echo $1 | awk -F',' '{print $3}')
        L_DOWNLOAD_LOCATION=$2
        if [ "$l_name" == "" ];
        then
                echo "No name for $l_repo:$l_tag"
                L_IMAGE=$(echo $l_repo":"$l_tag | tr -d '"')
        else
                L_IMAGE=$(echo $l_repo"/"$l_name":"$l_tag | tr -d '"')
        fi
        echo "Downloading image - ${L_IMAGE} to ${L_DOWNLOAD_LOCATION}."
        docker pull ${L_IMAGE}
        docker save ${L_IMAGE} -o ${L_DOWNLOAD_LOCATION}/$(echo "${L_IMAGE}" | tr '/' ',')
}
#End get_image
get_tkg_images()
{
        echo "Getting the tkg images"
        mkdir -p ${DOWNLOAD_LOCATION}/${TKG_IMAGES_DIR}
        L_TKG_TMP_DIR=${TMP_BASE_DIR}/tkg
        L_CLIENT_ARCH=$(uname | tr '[:upper:]' '[:lower:]')
        mkdir -p ${L_TKG_TMP_DIR}
        # Get the tanzu command line and use it to create the needed BOM.
#       tar xv -C ${L_TKG_TMP_DIR} --strip-components 3  -f ${DOWNLOAD_LOCATION}/${TKG_DIR}/tanzu-cli-bundle-v${CLI_VERSION}-${L_CLIENT_ARCH}-amd64.tar cli/core/v${CLI_VERSION}/tanzu-core-${L_CLIENT_ARCH}_amd64
        tar xv -C ${L_TKG_TMP_DIR} -f ${DOWNLOAD_LOCATION}/${TKG_DIR}/tanzu-cli-bundle-v${CLI_VERSION}-${L_CLIENT_ARCH}-amd64.tar cli
        echo "Running commands to setup tanzu BOM."
        pushd ${L_TKG_TMP_DIR}
                chmod +x ${L_TKG_TMP_DIR}/cli/core/v${CLI_VERSION}/tanzu-core-${L_CLIENT_ARCH}_amd64
                ${L_TKG_TMP_DIR}/cli/core/v${CLI_VERSION}/tanzu-core-${L_CLIENT_ARCH}_amd64 plugin install --local cli all
                ${L_TKG_TMP_DIR}/cli/core/v${CLI_VERSION}/tanzu-core-${L_CLIENT_ARCH}_amd64 init
                ${L_TKG_TMP_DIR}/cli/core/v${CLI_VERSION}/tanzu-core-${L_CLIENT_ARCH}_amd64 management-cluster create > /dev/null
        popd

        ./download-images.sh ${DOWNLOAD_LOCATION}/${TKG_IMAGES_DIR} > ${L_TKG_TMP_DIR}/pull-and-save-images.sh
        chmod +x  ${L_TKG_TMP_DIR}/pull-and-save-images.sh
        ${L_TKG_TMP_DIR}/pull-and-save-images.sh
}
# End get_tkg
get_extension_images()
{
        echo "Getting extension images."
        mkdir -p ${TMP_BASE_DIR}/extensions
        mkdir -p ${DOWNLOAD_LOCATION}/${EXTENSIONS_IMAGE_DIR}

        cp ${DOWNLOAD_LOCATION}/${TKG_DIR}/*extensions-manifests*.tar.gz ${TMP_BASE_DIR}/extensions

        pushd ${TMP_BASE_DIR}/extensions

        tar xfz tkg-extensions-manifests*
        for l_values_file in $(find . -name values.yaml)
        do
                #echo "Processing images found in [${l_values_file}]"
                l_extension=$(echo ${l_values_file} | awk -F'/' '{print $3}')
                case ${l_extension} in
                        ingress|monitoring|authentication|logging|service-discovery|registry)
                                IMAGES=$(yq -j e '.. | select(has("image"))|.image'  ${l_values_file} | grep -v null)
                                for image in $(echo $IMAGES| jq -r '[.repository, .name, .tag]| @csv' )
                                do
                                        get_image $image ${DOWNLOAD_LOCATION}/${EXTENSIONS_IMAGE_DIR}
                                done
                                ;;
                        *)
                                echo -e "${RED}Unknown format.  Check for what should be done!${NC}" >&2
                                ;;
                esac
        done

        popd

}
# End get_extension_images

# Main processing
validate
get-tkg-components
#get_tkg_images
#get_extension_images
