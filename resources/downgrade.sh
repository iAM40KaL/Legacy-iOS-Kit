#!/bin/bash

FRBaseband() {
    local BasebandSHA1L
    
    if [[ $DeviceProc == 7 ]]; then
        mkdir -p saved/baseband 2>/dev/null
        cp -f $IPSWRestore/Firmware/$Baseband saved/baseband
    fi

    if [[ ! -e saved/baseband/$Baseband ]]; then
        Log "Downloading baseband..."
        $partialzip $BasebandURL Firmware/$Baseband $Baseband
        $partialzip $BasebandURL BuildManifest.plist BuildManifest.plist
        mkdir -p saved/$ProductType saved/baseband 2>/dev/null
        mv $Baseband saved/baseband
        mv BuildManifest.plist saved/$ProductType
        BuildManifest="saved/$ProductType/BuildManifest.plist"
    elif [[ $DeviceProc != 7 ]]; then
        BuildManifest="saved/$ProductType/BuildManifest.plist"
    fi

    BasebandSHA1L=$(shasum saved/baseband/$Baseband | awk '{print $1}')
    if [[ ! -e $(ls saved/baseband/$Baseband) || $BasebandSHA1L != $BasebandSHA1 ]]; then
        rm -f saved/baseband/$Baseband saved/$ProductType/BuildManifest.plist
        if [[ $DeviceProc == 7 ]]; then
            Error "Downloading/verifying baseband failed. Please run the script again"
        else
            Log "Downloading/verifying baseband failed, will proceed with --latest-baseband flag"
            return 1
        fi
    fi
}

FutureRestore() {
    local ExtraArgs=()

    Log "Proceeding to futurerestore..."
    if [[ $IPSWA7 != 1 ]]; then
        ExtraArgs+=("--use-pwndfu")
        cd resources
        $SimpleHTTPServer &
        ServerPID=$!
        cd ..
    fi

    if [[ $DeviceProc == 7 ]]; then
        ExtraArgs+=("-s" "$IPSWRestore/Firmware/all_flash/$SEP" "-m" "$BuildManifest")
        if [[ $IPSWA7 != 1 ]]; then
            # Send dummy file for device detection
            $irecovery -f README.md
            sleep 2
        fi
    elif [[ $SendiBSS != 1 ]]; then
        ExtraArgs+=("--no-ibss")
    fi

    if [[ $Baseband == 0 ]]; then
        Log "Device $ProductType has no baseband"
        ExtraArgs+=("--no-baseband")
    else
        FRBaseband
        if [[ $? == 1 ]]; then
            ExtraArgs+=("--latest-baseband")
        else
            ExtraArgs+=("-b" "saved/baseband/$Baseband" "-p" "$BuildManifest")
        fi
    fi

    Log "Running futurerestore with command: $futurerestore -t \"$SHSH\" ${ExtraArgs[*]} \"$IPSWRestore.ipsw\""
    $futurerestore -t "$SHSH" "${ExtraArgs[@]}" "$IPSWRestore.ipsw"
    if [[ $? != 0 ]]; then
        Log "An error seems to have occurred in futurerestore."
        Echo "* Please read the \"Troubleshooting\" wiki page in GitHub before opening any issue!"
        Echo "* Your problem may have already been addressed within the wiki page."
        Echo "* If opening an issue in GitHub, please provide a FULL log. Otherwise, your issue may be dismissed."
    else
        echo
        Log "Restoring done!"
    fi
    Log "Downgrade script done!"
}

DowngradeOther() {
    Input "Select your IPSW file in the file selection window."
    IPSW="$($zenity --file-selection --file-filter='IPSW | *.ipsw' --title="Select IPSW file")"
    [[ ! -s "$IPSW" ]] && Error "No IPSW selected, or IPSW file not found."
    IPSW="${IPSW%?????}"
    Log "Selected IPSW file: $IPSW.ipsw"
    Input "Select your SHSH file in the file selection window."
    SHSH="$($zenity --file-selection --file-filter='SHSH | *.shsh *.shsh2' --title="Select SHSH file")"
    [[ ! -s "$SHSH" ]] && Error "No SHSH selected, or SHSH file not found."
    Log "Selected SHSH file: $SHSH"

    unzip -o -j "$IPSW.ipsw" Restore.plist -d tmp
    BuildVer=$(cat tmp/Restore.plist | grep -i ProductBuildVersion -A 1 | grep -oPm1 "(?<=<string>)[^<]+")
    if [[ ! -e resources/firmware/$ProductType/$BuildVer/index.html ]]; then
        Log "Getting firmware keys for $ProductType-$BuildVer"
        mkdir -p resources/firmware/$ProductType/$BuildVer 2>/dev/null
        curl -L https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/raw/master/$ProductType/$BuildVer/index.html -o tmp/index.html
        mv tmp/index.html resources/firmware/$ProductType/$BuildVer
    fi

    kDFU
    IPSWSetExtract
    FutureRestore
}

DowngradeOTA() {
    if [[ $DeviceProc != 7 ]]; then
        JailbreakOption
    fi
    SaveOTABlobs
    IPSWFindVerify
    kDFU
    if [[ $Jailbreak == 1 || $ProductType == "iPad2,3" ]]; then
        IPSW32
    else
        IPSWCustom=0
    fi
    IPSWSetExtract
    FutureRestore
}

DowngradeOTAWin() {
    IPSWCustom="${IPSWType}_${OSVer}_${BuildVer}_CustomWin"
    if [[ $DeviceProc != 7 ]]; then
        JailbreakOption
        SaveOTABlobs
    fi
    IPSWFindVerify
    if [[ $DeviceProc == 7 ]]; then
        IPSWA7=1
        IPSWSetExtract
        IPSW64
        EnterPwnREC
        local APNonce=$($irecovery -q | grep "NONC" | cut -c 7-)
        Log "APNONCE: $APNonce"
        SaveOTABlobs $APNonce
        IPSWSetExtract set
        FutureRestore
        return
    fi
    kDFU
    IPSW32
    IPSWSetExtract
    iDeviceRestore
}

IPSWCustomA7() {
    if [[ $platform == "macos" ]]; then
        fr194=("https://github.com/futurerestore/futurerestore/releases/download/194/futurerestore-v194-macOS.tar.xz" "d279423dd9a12d3a7eceaeb7e01beb332c306aaa")
    elif [[ $platform == "linux" ]]; then
        fr194=("https://github.com/futurerestore/futurerestore/releases/download/194/futurerestore-v194-ubuntu_20.04.2.tar.xz" "9f2b4b6cc6710d1d68880711001d2dc5b4cb9407")
    fi
    Input "Custom IPSW Option"
    Echo "* When this option is enabled, a custom IPSW will be created/used for restoring."
    Echo "* Only enable this when you encounter problems with futurerestore."
    Echo "* This option is disabled by default (N)."
    read -p "$(Input 'Enable this option? (y/N):')" IPSWA7
    if [[ $IPSWA7 != 'Y' && $IPSWA7 != 'y' ]]; then
        return
    fi
    IPSWA7=1
    Log "Custom IPSW option enabled by user."
    futurerestore="./resources/tools/futurerestore194_$platform"
    if [[ ! -e $futurerestore ]]; then
        cd tmp
        SaveFile ${fr194[0]} futurerestore.tar.xz ${fr194[1]}
        7z x futurerestore.tar.xz
        tar -xf futurerestore*.tar
        chmod +x futurerestore-v194
        mv futurerestore-v194 ../$futurerestore
        cd ..
    fi
 }

Downgrade() {
    Log "Select your options when asked. If unsure, go for the defaults (press Enter/Return)."
    echo

    if [[ $DeviceProc == 7 && $platform != "win" ]]; then
        IPSWCustomA7
    fi

    if [[ $platform == "win" || $IPSWA7 == 1 ]]; then
        DowngradeOTAWin
        return
    elif [[ $OSVer == "Other" ]]; then
        DowngradeOther
        return
    fi
    DowngradeOTA
}

iDeviceRestore() {
    mkdir shsh
    cp $SHSH shsh/${UniqueChipID}-${ProductType}-${OSVer}.shsh
    Log "Proceeding to idevicerestore..."
    [[ $platform == "macos" ]] && sudo codesign --sign - --force --deep $idevicerestore
    [[ $1 == "latest" ]] && ExtraArgs="-ey" || ExtraArgs="-ewy"
    $idevicerestore $ExtraArgs "$IPSWRestore.ipsw"
    if [[ $platform == "macos" && $? != 0 ]]; then
        Log "Restoring done! Read the message below if any error has occurred:"
        Echo "* If the \"Killed: 9\" or other similar error pops up, try these steps:"
        Echo "* Using Terminal, cd to where the script is located, then run"
        Echo "* sudo codesign --sign - --force --deep resources/tools/idevicerestore_macos"
        Echo "* For more details, read the \"Troubleshooting\" wiki page in GitHub"
    elif [[ $platform == "win" && $? != 0 ]]; then
        Log "Restoring done! Read the message below if any error has occurred:"
        Echo "* Windows users may encounter errors like \"Unable to send APTicket\" or \"Unable to send iBEC\" in the restore process."
        Echo "* To fix this, follow troubleshooting steps from here: https://github.com/LukeZGD/iOS-OTA-Downgrader/wiki/Troubleshooting#windows"
    else
        echo
        Log "Restoring done!"
    fi
    Log "Downgrade script done!"
}

Downgrade4() {
    JailbreakOption
    IPSWFindVerify
    Save712Blobs
    if [[ $OSVer == "7.1.2" && $Jailbreak != 1 ]]; then
        IPSWSetExtract
        iDeviceRestore latest
        return
    elif [[ $OSVer != "7.1.2" ]]; then
        IPSWFindVerify 712
    fi
    IPSW4
    IPSWSetExtract
    iDeviceRestore
}
