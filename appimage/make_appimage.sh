#!/bin/bash

# Helper file for generating a SER Player Linux AppImage
# ------------------------------------------------------
# This file is designed for to be used on Ubuntu 22.04 (Jammy)
# Either 64-bit or 32-bit depending on the version of
# AppImage required.
#
# From ser-player.pro folder enter this on the command line:
# source appimage/make_appimage.sh
#

MACHINE_ARCH=`uname -m`
if [ ${MACHINE_ARCH} != 'x86_64' ]; then
  # 32-bit
  MACHINE_ARCH='i686'
fi

# Clean up any previous attempts to build an AppImage
rm -rf bin build appdir
rm -f *.AppImage

# Ensure the system is up to date
sudo apt-get update -qq
sudo apt-get upgrade

# Install some required packages
sudo apt-get -y install build-essential libgl1-mesa-dev libpng-dev

# Get the correct version of Qt
sudo add-apt-repository ppa:beineri/opt-qt-6.6.0-jammy -y
sudo apt-get update -qq
sudo apt-get -y install qt6-base-dev qt6-base-dev-tools

# Configure Qt6 environment
export QT_SELECT=qt6

# Build the SER Player binary
qmake6 CONFIG+=release BUILD_FOR_APPIMAGE=
make -j$(nproc)
ls -l bin/
ldd bin/ser-player
make INSTALL_ROOT=appdir -j$(nproc) install
find appdir/

# Download linuxdeploy and plugin for Qt6 instead of building linuxdeployqt
wget -c "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage"
wget -c "https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-x86_64.AppImage"
chmod a+x linuxdeploy-x86_64.AppImage linuxdeploy-plugin-qt-x86_64.AppImage

# Get and build patchelf if required
type patchelf >/dev/null 2>&1 || {
  wget https://nixos.org/releases/patchelf/patchelf-0.9/patchelf-0.9.tar.bz2
  tar xf patchelf-0.9.tar.bz2
  ( cd patchelf-0.9/ && ./configure && make && sudo make install )
  
  # Clean up
  rm -rf patchelf-0.9
  rm patchelf-0.9.*
}

# Get appimagetool AppImage
wget -c -nv "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-$MACHINE_ARCH.AppImage"
chmod a+x "appimagetool-$MACHINE_ARCH.AppImage"

# Load version information
if [ -f export_app_version.sh ]; then
  source export_app_version.sh
else
  VERSION="unknown"
fi

# Make sure the desktop file exists
if [ ! -f appdir/usr/share/applications/com.google.sites.ser-player.desktop ]; then
  mkdir -p appdir/usr/share/applications/
  cat > appdir/usr/share/applications/com.google.sites.ser-player.desktop <<EOL
[Desktop Entry]
Type=Application
Name=SER Player
Comment=SER Player is an open source video player for playing SER files
Exec=ser-player %F
Icon=ser-player
Terminal=false
Categories=Graphics;2DGraphics;Viewer;
MimeType=application/x-ser;
EOL
fi

# Find the exact path to the desktop file
DESKTOP_FILE=$(find appdir/usr/share/applications/ -name "*.desktop" | head -n 1)
echo "Using desktop file: $DESKTOP_FILE"

# Configure Qt6 paths for linuxdeploy
export QT_PLUGIN_PATH=/usr/lib/x86_64-linux-gnu/qt6/plugins/

# Use linuxdeploy to generate a populated appdir
unset QTDIR; unset LD_LIBRARY_PATH
export QMAKE=/usr/lib/qt6/bin/qmake

# Run linuxdeploy with Qt plugin and explicit desktop file
./linuxdeploy-x86_64.AppImage --appdir=appdir --plugin=qt --executable=bin/ser-player --desktop-file="$DESKTOP_FILE"

# Remove AppRun symbolic link created by linuxdeploy in appdir if it exists
if [ -L appdir/AppRun ]; then
  rm -f appdir/AppRun
fi

# Create a script to replace the deleted AppRun link
cat > appdir/AppRun <<EOL
#!/bin/bash

if [[ \$1 == --install ]]; then
    echo "Installing SER Player ($VERSION) to desktop"
    # Copy desktop file, icon files and mime file to the system
    cp -r "\$APPDIR/usr/share/" "\$HOME/.local/"
    
    # Modify desktop file to point to AppImage
    rm -f "\$HOME/.local/share/applications/com.google.sites.ser-player.desktop"
    cat "\$APPDIR/usr/share/applications/com.google.sites.ser-player.desktop" | sed -e "s:Exec=ser-player \%F:Exec=\$HOME/.local/bin/ser-player \%F:" > "\$HOME/.local/share/applications/com.google.sites.ser-player.desktop"

    # Copy the actual AppImage into $HOME/.local/bin/
    mkdir -p "\$HOME/.local/bin/"
    cp \$APPIMAGE "\$HOME/.local/bin/ser-player"

    # Update icon cache
    type gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache "\$HOME/.local/share/icons/hicolor/" -t
    # Update mime to filetype database
    type update-mime-database >/dev/null 2>&1 && update-mime-database "\$HOME/.local/share/mime/"
    # Update mime to application database
    type update-desktop-database >/dev/null 2>&1 && update-desktop-database "\$HOME/.local/share/applications/"

elif [[ \$1 == --uninstall ]]; then
    echo "Uninstalling SER Player from desktop"
    # Delete icon files
    find "\$HOME/.local/share/icons/hicolor/" -name "ser-player.*" -exec rm -f {} \;
    # Delete mime file
    rm -f "\$HOME/.local/share/mime/packages/ser-player.xml"
    # Delete desktop file
    rm -f "\$HOME/.local/share/applications/com.google.sites.ser-player.desktop"
    # Delete the application binary
    rm -f "\$HOME/.local/bin/ser-player"

    # Update icon cache
    type gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache "\$HOME/.local/share/icons/hicolor/" -t
    # Update mime to filetype database
    type update-mime-database >/dev/null 2>&1 && update-mime-database "\$HOME/.local/share/mime/"
    # Update mime to application database
    type update-desktop-database >/dev/null 2>&1 && update-desktop-database "\$HOME/.local/share/applications/"

elif [[ \$1 == --help ]]; then
    echo "SER Player ($VERSION) AppImage Command Line Arguments"
    echo "  --help       Display this help."
    echo "  --install    Install SER Player to desktop and associate with .ser files."
    echo "  --uninstall  Uninstall SER Player from Desktop and remove associations."
    echo

else
    exec "\$APPDIR/usr/bin/ser-player" "\$@"
fi
EOL
chmod a+x appdir/AppRun

# Make sure all directories exist
mkdir -p appdir/usr/bin/
mkdir -p appdir/usr/share/mime/packages/

# Copy the binary if it's not already there
if [ ! -f appdir/usr/bin/ser-player ]; then
  cp bin/ser-player appdir/usr/bin/
fi

# Ensure icon files are present
mkdir -p appdir/usr/share/icons/hicolor/256x256/apps/
if [ -f platform-specific/linux/icons/256x256/ser-player.png ]; then
  cp platform-specific/linux/icons/256x256/ser-player.png appdir/usr/share/icons/hicolor/256x256/apps/
fi

# Ensure mime type file is present 
if [ -f platform-specific/linux/ser-player.xml ]; then
  cp platform-specific/linux/ser-player.xml appdir/usr/share/mime/packages/
fi

# Use appimagetool to create the final AppImage from the appdir
./appimagetool-$MACHINE_ARCH.AppImage -v appdir
