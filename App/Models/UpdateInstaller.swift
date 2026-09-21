//
//  UpdateInstaller.swift
//  Recap
//
//  Created by Rio on 9/21/26.
//

import Foundation

enum UpdateInstaller {

    struct Plan {
        let appURL: URL
        let workingDirectory: URL
        let processID: Int32
        let expectedVersion: String
        let helperURL: URL
        let logURL: URL
        let readyURL: URL
        let stagedAppURL: URL
        let backupAppURL: URL

        private let cancelURL: URL
        private let validPaths: Bool

        init(appURL: URL, workingDirectory: URL, processID: Int32, expectedVersion: String) {
            let parent = appURL.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
            let application = parent.appendingPathComponent(appURL.lastPathComponent, isDirectory: true)
            let directory = workingDirectory.standardizedFileURL.resolvingSymlinksInPath()
            let identifier = UUID().uuidString
            self.appURL = application
            self.workingDirectory = directory
            self.processID = processID
            self.expectedVersion = expectedVersion
            helperURL = directory.appendingPathComponent("install.sh")
            logURL = directory.appendingPathComponent("install.log")
            readyURL = directory.appendingPathComponent("ready")
            cancelURL = directory.appendingPathComponent("cancel")
            stagedAppURL = parent.appendingPathComponent(".Recap-update-\(identifier).app", isDirectory: true)
            backupAppURL = parent.appendingPathComponent(".Recap-backup-\(identifier).app", isDirectory: true)
            validPaths = appURL.isFileURL && workingDirectory.isFileURL
                && appURL.pathExtension == "app" && processID > 1 && !expectedVersion.isEmpty
                && directory.path != "/" && directory != parent && directory != application
                && !directory.path.hasPrefix(application.path + "/")
                && !application.path.hasPrefix(directory.path + "/")
        }

        // Prepare a signed copy beside the installed app without touching the running bundle.
        func preparationCommand(dmgURL: URL) -> String {
            guard validPaths, dmgURL.isFileURL else { return "exit 1" }
            return #"""
            set -euo pipefail
            PATH=/usr/bin:/bin:/usr/sbin:/sbin
            export PATH
            umask 077
            \#(variables)
            dmg=\#(Self.quote(dmgURL.path))
            expected_version=\#(Self.quote(expectedVersion))
            mount="$work/mount"
            [[ -d "$work" && ! -L "$work" ]] || exit 1
            [[ -d "$app" && ! -L "$app" ]] || exit 1
            [[ -f "$dmg" && ! -L "$dmg" ]] || exit 1
            [[ ! -e "$staged" && ! -L "$staged" ]] || exit 1
            [[ ! -e "$backup" && ! -L "$backup" ]] || exit 1
            [[ ! -e "$mount" && ! -L "$mount" ]] || exit 1
            [[ ! -e "$ready" && ! -L "$ready" ]] || exit 1
            [[ ! -e "$cancel" && ! -L "$cancel" ]] || exit 1
            [ ! -L "$log" ] || exit 1
            exec >>"$log" 2>&1
            mounted=0
            prepared=0
            finish() {
                result=$?
                trap - EXIT
                if [ "$mounted" -eq 1 ]; then
                    if ! /usr/bin/hdiutil detach -quiet "$mount"; then
                        printf '%s\n' 'Could not detach update image.'
                        result=1
                    fi
                fi
                if [ "$prepared" -eq 0 ] && [ -d "$app" ] && [ ! -L "$app" ]; then
                    /bin/rm -rf "$staged"
                fi
                /bin/rmdir "$mount" 2>/dev/null || true
                exit "$result"
            }
            trap finish EXIT
            trap 'exit 130' INT
            trap 'exit 143' TERM HUP
            /bin/mkdir "$mount"
            mounted=1
            /usr/bin/hdiutil attach -readonly -nobrowse -quiet -mountpoint "$mount" "$dmg"
            source="$mount/Recap.app"
            [[ -d "$source" && ! -L "$source" ]] || exit 1
            [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$source/Contents/Info.plist")" = 'com.rio.Recap' ] || exit 1
            [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$source/Contents/Info.plist")" = "$expected_version" ] || exit 1
            [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" = 'com.rio.Recap' ] || exit 1
            /usr/bin/codesign --verify --deep --strict "$app"
            /usr/bin/codesign --verify --deep --strict "$source"
            current_team=$(/usr/bin/codesign -d --verbose=4 "$app" 2>&1 | /usr/bin/sed -n 's/^TeamIdentifier=//p')
            update_team=$(/usr/bin/codesign -d --verbose=4 "$source" 2>&1 | /usr/bin/sed -n 's/^TeamIdentifier=//p')
            [[ "$current_team" =~ ^[A-Z0-9]{10}$ ]] || exit 1
            [ "$current_team" = "$update_team" ] || exit 1
            /usr/bin/ditto "$source" "$staged"
            /usr/bin/codesign --verify --deep --strict "$staged"
            /usr/bin/hdiutil detach -quiet "$mount"
            mounted=0
            prepared=1
            printf '%s\n' 'Update prepared; the running application has not been changed.'
            """#
        }

        // The detached helper waits for an ordinary application termination before replacing it.
        func helperScript(waitAttempts: Int = 120, waitInterval: Double = 0.5, relaunch: Bool = true) -> String {
            guard validPaths, waitAttempts > 0, waitInterval.isFinite, waitInterval > 0 else { return "exit 1\n" }
            return #"""
            #!/bin/bash
            set -euo pipefail
            PATH=/usr/bin:/bin:/usr/sbin:/sbin
            export PATH
            umask 077
            \#(variables)
            old_pid=\#(processID)
            old_moved=0
            new_installed=0
            finish() {
                result=$?
                trap - EXIT
                if [ "$old_moved" -eq 1 ] && [ "$new_installed" -eq 0 ]; then
                    if [ ! -e "$app" ] && [ ! -L "$app" ] && [ -d "$backup" ] && [ ! -L "$backup" ]; then
                        if /bin/mv "$backup" "$app"; then
                            printf '%s\n' 'The previous application was restored.'
                        else
                            printf 'Restore failed; the previous application remains at %s\n' "$backup"
                        fi
                    fi
                fi
                if [ -d "$app" ] && [ ! -L "$app" ]; then
                    /bin/rm -rf "$staged"
                    if [ "$new_installed" -eq 1 ] && [ "$result" -eq 0 ]; then
                        /bin/rm -rf "$backup"
                    fi
                fi
                printf 'Update helper finished with status %s.\n' "$result"
                exit "$result"
            }
            trap finish EXIT
            trap 'exit 130' INT
            trap 'exit 143' TERM HUP
            [[ -d "$work" && ! -L "$work" ]] || exit 1
            [[ -d "$app" && ! -L "$app" ]] || exit 1
            [[ -d "$staged" && ! -L "$staged" ]] || exit 1
            [[ ! -e "$backup" && ! -L "$backup" ]] || exit 1
            [[ ! -e "$ready" && ! -L "$ready" ]] || exit 1
            [[ ! -e "$cancel" && ! -L "$cancel" ]] || exit 1
            printf '%s\n' "$$" >"$ready"
            printf 'Waiting for application process %s to exit.\n' "$old_pid"
            attempt=0
            while /bin/kill -0 "$old_pid" 2>/dev/null || /bin/ps -p "$old_pid" -o pid= >/dev/null 2>&1; do
                [ ! -e "$cancel" ] || { printf '%s\n' 'Update cancelled.'; exit 1; }
                if [ "$attempt" -ge \#(waitAttempts) ]; then
                    printf '%s\n' 'The application is still running; update cancelled without replacing it.'
                    exit 1
                fi
                /bin/sleep \#(waitInterval)
                attempt=$((attempt + 1))
            done
            [ ! -e "$cancel" ] || exit 1
            [[ -d "$staged" && ! -L "$staged" ]] || exit 1
            [[ -d "$app" && ! -L "$app" ]] || exit 1
            [[ ! -e "$backup" && ! -L "$backup" ]] || exit 1
            old_moved=1
            /bin/mv "$app" "$backup"
            /bin/mv "$staged" "$app"
            new_installed=1
            printf '%s\n' 'Update installed after the previous process exited.'
            \#(relaunch ? "/usr/bin/open \"$app\"" : ":")
            """# + "\n"
        }

        // Readiness acknowledges the helper before the caller requests application termination.
        func launchCommand() -> String {
            guard validPaths else { return "exit 1" }
            return #"""
            set -euo pipefail
            umask 077
            \#(variables)
            helper=\#(Self.quote(helperURL.path))
            [[ -d "$work" && ! -L "$work" ]] || exit 1
            [[ -f "$helper" && ! -L "$helper" ]] || exit 1
            [[ ! -e "$ready" && ! -L "$ready" ]] || exit 1
            [[ ! -e "$cancel" && ! -L "$cancel" ]] || exit 1
            [ ! -L "$log" ] || exit 1
            /usr/bin/nohup /bin/bash "$helper" >>"$log" 2>&1 </dev/null &
            helper_pid=$!
            attempt=0
            while [ "$attempt" -lt 100 ]; do
                if [ -f "$ready" ] && [ ! -L "$ready" ]; then exit 0; fi
                /bin/kill -0 "$helper_pid" 2>/dev/null || exit 1
                /bin/sleep 0.05
                attempt=$((attempt + 1))
            done
            [[ ! -L "$cancel" ]] || exit 1
            : >"$cancel"
            exit 1
            """#
        }

        // Leave logs and any recovery backup intact; a started helper owns its own cleanup.
        func cleanupCommand() -> String {
            guard validPaths else { return "exit 1" }
            return #"""
            set -eu
            \#(variables)
            [[ -d "$work" && ! -L "$work" ]] || exit 1
            [[ ! -L "$cancel" ]] || exit 1
            : >"$cancel"
            if [ ! -e "$ready" ] && [ ! -L "$ready" ] && [ -d "$app" ] && [ ! -L "$app" ] && [ ! -e "$backup" ] && [ ! -L "$backup" ]; then
                /bin/rm -rf "$staged"
            fi
            """#
        }

        private var variables: String {
            """
            app=\(Self.quote(appURL.path))
            work=\(Self.quote(workingDirectory.path))
            staged=\(Self.quote(stagedAppURL.path))
            backup=\(Self.quote(backupAppURL.path))
            ready=\(Self.quote(readyURL.path))
            cancel=\(Self.quote(cancelURL.path))
            log=\(Self.quote(logURL.path))
            """
        }

        private static func quote(_ value: String) -> String {
            "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
    }
}
