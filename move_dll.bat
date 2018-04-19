mkdir local64\mpv_root\build
copy build\mpv-git\build\mpv-1.dll local64\mpv_root\build\mpv.dll
bin\cv2pdb -C local64\mpv_root\build\mpv.dll