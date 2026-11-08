rm -rf Phientist.AppDir
mkdir Phientist.AppDir
cp -r build/linux/x64/release/bundle/* Phientist.AppDir
cp -r buildtools/appimage_config/* Phientist.AppDir
cp buildtools/icon-padded.png Phientist.AppDir
sudo chmod +x buildtools/appimagetool-x86_64.AppImage
sudo chmod +x Phientist.AppDir/AppRun
./buildtools/appimagetool-x86_64.AppImage Phientist.AppDir
