#!/bin/bash

set -ex

#2DO
#CHECK and INSTALL dependences from debian/control file
# apt-get install debhelper quilt devscripts equivs
# also you'll need different dh-* stuff, like for ex. dh-translation

#VERBOSE:
export DH_VERBOSE=1

#Skip code checks:
export DEB_BUILD_OPTIONS="nocheck"

# Usual locale:
export LC_ALL="en_US.UTF-8"

#Trying make it faster:
export NUMJOBS=" -j$(nproc)"
#alias make="make -j$(nproc)"

# should be parameters one day:
#CFLAGS="-march=native -O2 -pipe -fPIC"
CFLAGS="-march=native -O3 -pipe -fPIC"
BUILD_DIR_NAME="BUILD"
PKGS_DIR_NAME="PKGS"
VERSION_SUFFIX="native"
SLEEP_TIME=5
START_DATE=$(date +%Y%m%d%H%M)

#show that package was built with -O3:
if [ ! -z "$(echo ${CFLAGS}| grep O3)" ]; then
    VERSION_SUFFIX=${VERSION_SUFFIX}-O3
fi

CURRENT_DIR=`pwd`
BUILD_DIR=${CURRENT_DIR}/${BUILD_DIR_NAME}
PKGS_DIR=${CURRENT_DIR}/${PKGS_DIR_NAME}



#publishing:
REPO_NAME=native-19.10 #here should be ubuntu version
REPO_DIR=ubuntu
COMPONENT="main"
DISTRIBUTION="native"
ORIGIN="Native Linux"
LABEL="Native Linux"
ARCH="all,amd64,i386"

#INFO:
#uname -a | sudo tee native_flags_${START_DATE}.txt
#echo "GCC flags will be:"
#gcc ${CFLAGS} -E -v - </dev/null 2>&1 | grep cc1 | sudo tee native_flags.txt

#cflags normalization:
NEW_CFLAGS=$(gcc ${CFLAGS} -E -v - </dev/null 2>&1 | grep cc1 | sed 's/.* - //')
#echo "GCC flags will be: ${NEW_CFLAGS}"

#IMPORTANT: Dependencies
# apt-get install debhelper

#ALSO:  I used 'devscripts' previously, but not now.

# Instaled packages list:
#PKGS_LIST=`dpkg -l | awk '{print $2}' | tee PKGS_LIST.txt`

## Manual example:
# apt-get source mc
# apt-get build-dep mc
# apt-get install devscripts
# export CFLAGS="-march=native -O2 -pipe -fPIC" CXXFLAGS="${CFLAGS}"
# where "-march=native -O2 -pipe" - persistent part,
# and " -fPIC" - custom flag for mc, if will fail the build w/o it.
#
## build command:
# debuild -uc -us -j4

## you have to build an app for performance testing (like squashfs-tools or p7zip),
## and benchmark debian compiled app against locally compiled one.

### Aptly ###

# aptly repo create

# aptly repo add -force-replace=true -remove-files=false  PKGS/

# aptly publish repo -component="main" -distribution="native" -label="Native Linux" -origin="Native Linux" -architectures="all,amd64,i386" native ubuntu

# aptly publish update native


######## (signup repos) GPG stuff:##
## generate (choose HW node to generate)
# gpg --gen-key
## copy ~/.gnupg folder to a target machine
## list:
# gpg -k
## create text file:
# gpg --armor --output yourname-pub-sub.asc --export 'Your Name'
## add to apt:
# sudo apt-key add your_key.asc
####################################

#TODO:

# 1. Docker file, or LXC container for packages building.
# 2. Jenkins VM - as a part of the future CI system.

print_help(){
    echo -e "USAGE: \n $0 package_name1 package_name2 etc."
}

ERROR_EXIT(){
    echo -e "ERROR: \n$@"
    exit 1
}

clean_ws(){
#    rm -rf ${BUILD_DIR}.old
#    mv ${BUILD_DIR} ${BUILD_DIR}.old
    rm -rf ${BUILD_DIR}
}

mk_workspace(){
    clean_ws
    sudo mkdir -p ${BUILD_DIR} ${PKGS_DIR}
    sudo chown -R $USER:$USER ${BUILD_DIR}
    sudo chown -R $USER:$USER ${PKGS_DIR}
    cd ${BUILD_DIR}
}

export_flags(){

    export CFLAGS=${NEW_CFLAGS}
    export CXXFLAGS="${CFLAGS}"
}

prepare(){

    local PACKAGE="$1"
#    sudo apt-get -y source ${PACKAGE}
#    sudo apt-get -y build-dep ${PACKAGE}
    COMMON_NAME=$(apt-get -y source ${PACKAGE} | grep -m1 "^Picking" | awk '{print $2}' | tr -d "'" )
    if [ ! -z "${COMMON_NAME}" ]; then
        PKG_DIR=${COMMON_NAME}
    else
        PKG_DIR=${PACKAGE}
    fi

}

quilt_patch(){
    export QUILT_PATCHES=debian/patches
    export QUILT_REFRESH_ARGS="-p ab --no-timestamps --no-index"
    quilt push -a

}

update_version(){
    # assume package was not buit yet.
    # to rebuild the package, you have to remove sources.
    PKG_BUILT=0
    # should be executed inside package folder:
    OLD_VERSION=`head -n1 debian/changelog | awk -v FS="[()]" '{ print $2;}'`
    if echo ${OLD_VERSION} | grep "${VERSION_SUFFIX}"; then
        echo "Version suffix already there: ${OLD_VERSION}"
#FIXME: if cleanup disabled,
#then new version doesn't mean that package is built, check that package exists
        echo "Skipping build"
        PKG_BUILT=1
    else
        NEW_VERSION=${OLD_VERSION}-${VERSION_SUFFIX}
        # Assume we have only one unic version there,
        # In the future instead of substitution -
        # new changelog section should be created.
        mv debian/changelog debian/changelog.orig
        sed "s/$OLD_VERSION/$NEW_VERSION/g" debian/changelog.orig > debian/changelog
        echo New $pkg version: `head -n1 debian/changelog`
    fi
    #sleep to show "Skipping build"
    sleep ${SLEEP_TIME}

}

build_pkg(){
    for pkg in ${PKGS_LIST}; do
        cd ${BUILD_DIR}
        prepare ${pkg}
        echo "########## Building package ${PKG_DIR} ##########"
        sleep ${SLEEP_TIME}
        #fixing  permissions:
        sudo chown -R $USER:$USER ${PKG_DIR}*
        for i in `ls --hide="*.tar.gz" --hide="*.dsc"| grep ${PKG_DIR}`; do
            if [ -d ${i} ]; then
                cd ${i} || ERROR_EXIT "cannot cd ${i} "
                echo "my path is: $(pwd)"
                break
            fi
        done
        update_version
        #if package was not bult yet:
        if [ ${PKG_BUILT} = "0" ]; then
            #building packages:

            #fixing dpkg database:
            sudo apt-get install -f

            #install deps:
            sudo mk-build-deps --install \
                --tool='apt-get -o Debug::pkgProblemResolver=yes --no-install-recommends --yes' debian/control \
                                         || ERROR_EXIT "Install devscripts: sudo apt-get install devscripts equivs"
            fakeroot debian/rules clean  || ERROR_EXIT "check 'debian/rules clean' errors"

            export_flags
            fakeroot debian/rules build  || ERROR_EXIT "check 'debian/rules build' errors"
            fakeroot debian/rules binary || ERROR_EXIT "check 'debian/rules binary' errors"
            cd ${BUILD_DIR} && mv *.deb ${PKGS_DIR}/
        fi
    done
}

publish(){

    aptly repo create $REPO_NAME || echo "repo exists"
    aptly repo add -force-replace=true -remove-files=true ${REPO_NAME}  ../${PKGS_DIR}/
    if aptly publish list | grep $REPO_NAME ; then
        #if exists - drop it first:
        DROP_STR=$(aptly publish list | grep native | awk '{print $2}' |awk -F'/' '{print $2" "$1}')
        aptly publish drop ${DROP_STR}
        aptly publish repo -component="$COMPONENT" -distribution="$DISTRIBUTION" -label="$LABEL" -origin="$ORIGIN" -architectures="$ARCH" ${REPO_NAME} ${REPO_DIR}
    else
        aptly publish repo -component="$COMPONENT" -distribution="$DISTRIBUTION" -label="$LABEL" -origin="$ORIGIN" -architectures="$ARCH" ${REPO_NAME} ${REPO_DIR}
    fi

    # Recreate procedure covers more usecases than an update:
    # aptly publish update ${DISTRIBUTION} ${REPO_DIR}

}



PKGS_LIST="$@"

#for testing:
#PKGS_LIST="cron bc mc"

if [ -z "${PKGS_LIST}" ]; then
    print_help
    exit 1
fi

######## MAIN #########
mk_workspace
build_pkg
#publish

echo "DONE!"


