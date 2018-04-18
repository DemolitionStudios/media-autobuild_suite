mkdir local64\mpv_root
mkdir local64\mpv_root\include 
mkdir local64\mpv_root\include\libmpv
copy build\mpv-git\libmpv local64\mpv_root\include\libmpv
lib /MACHINE:X64 /def:build\mpv-git\build\mpv-1.def /OUT:local64\mpv_root\mpv.lib