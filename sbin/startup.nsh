set fs fs0
set root LABEL=%ROOTLABEL%
set args "initrd=%INITRD% rootwait rootdelay=3"

%fs%:
cd %fs%:\

if exist bzImage.efi then
    echo "Updating Linux Kernel from %fs%:\%BZIMAGE%"
    rm bzImage.efi
    cp %BZIMAGE% bzImage.efi
else
    cp %BZIMAGE% bzImage.efi
endif

echo "Launching Linux Kernel %fs%:\bzImage.efi"
bzImage.efi root=%root% ro %args%

