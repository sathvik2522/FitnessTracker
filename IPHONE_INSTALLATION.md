# Install PersonalFitness on an iPhone


## New Mac / clean checkout

1. Install full Xcode and the iOS platform components. Open Xcode once and complete its setup. Verified toolchain: Xcode 27.0; the app requires iOS 17+ and an Xcode version supporting your phone's installed iOS.
2. In Terminal:

   ```sh
   git clone https://github.com/sathvik2522/FitnessTracker.git
   cd FitnessTracker
   open PersonalFitness.xcodeproj
   ```

3. In **Xcode > Settings > Apple Accounts**, add your own Apple Account and complete Apple's agreements. No paid membership is needed for the free development workflow.
4. In the project navigator select the blue **PersonalFitness** project, then **TARGETS > PersonalFitness > Signing & Capabilities**. Enable **Automatically manage signing** and choose your actual **Personal Team**. Keep **HealthKit** enabled. Do not enable clinical records or background delivery.
5. Configure an available unique bundle identifier. The shared `com.personal.PersonalFitness` is a template and was unavailable during the owner's setup. Copy `Configuration/Local.xcconfig.example` to ignored `Configuration/Local.xcconfig`, set your identifier and actual team, or select values through Xcode. For an existing installation, retain its exact original identifier. Your original Mac's ignored configuration already retains its working signing values.

## Connect a new iPhone

1. Connect using a data-capable cable, unlock the phone and accept **Trust This Computer**.
2. In Xcode's run-destination menu choose **Manage Devices** and pair/prepare the phone using Device Hub. Choose the actual named phone, not a simulator or generic device.
3. On iPhone, enable **Settings > Privacy & Security > Developer Mode**, restart and confirm enabling it. The switch may only appear after pairing starts. [Apple Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).
4. In Xcode select **PersonalFitness** scheme and the physical phone, then press **Command-R**. Allow Xcode to register/provision the device if prompted. If macOS asks for codesign key access, enter your Mac password in the system prompt and choose **Always Allow**; never send passwords to someone else.
5. If launch is blocked as an untrusted developer, open **Settings > General > VPN & Device Management**, choose your own development identity and follow the Trust/restart instructions. Launch PersonalFitness from Home Screen afterward. [Apple device installation](https://help.apple.com/xcode/mac/current/en.lproj/dev5a825a1ca.html).
6. Stop Xcode debugging, unplug the cable and relaunch from Home Screen to verify independent use. Your Mac can shut down.

A different phone needs its own provisioning and Health authorization. On a different Mac, sign in and let Xcode prepare signing; don't copy private keys or provisioning files into GitHub. The source repository does not contain your diary or workouts. Read [data transfer limitations](docs/PRIVACY_AND_DATA.md) before replacing or erasing the old phone.

## Apple Health

Tap **Connect Apple Health** explicitly on Dashboard. Enable read categories for Resting Energy, Active Energy, Steps, Workouts and Weight. There should be no write request. To change access, open Health's profile menu > Privacy > Apps (or Apps and Services), then PersonalFitness. [Apple Health permissions](https://support.apple.com/en-us/108779).

Unlock the phone and refresh. No data may mean no samples or denied access; request completion is not proof of permission. Weight is the latest sample within the selected day, not a carried-forward last weight. Today is partial. Watch readings may sync later, and iOS can suspend the app: no instant/background refresh guarantee exists.

## After the October 17 UX update

Install over the existing app using its same identifier. No store reset or SwiftData migration is required. Existing Health reads are preserved; optional sleep requires **Sleep > Enable sleep insights** and the separate sleep read switch. Verify your existing diary and workout records before adding new ones, then follow the [updated user guide](docs/USER_GUIDE.md).

## After the October 18 final audit

Install over the existing app with the same identifier. The new optional meal-category column uses additive SwiftData migration; old entries remain Unassigned. Isolated legacy-store migration tests cover preservation, but verify your real phone's existing records after updating. HealthKit remains enabled; unused clinical-record/background-delivery entitlements were removed. No new write permission is requested.

Use **Progress → Export local data** and save to **Files → On My iPhone**. Check the JSON exists, then copy it off the phone. This is an export, with no in-app restore yet. Do not delete the app to renew signing.

## Every seven days: renew free signing

Reconnect the unlocked phone, open the same Xcode project, select the same team and bundle identifier and your phone, then **Command-R**. Repeat after the provisioning period expires, or before it if needed. **Do not delete the app or change the identifier to renew it**; updating in place normally preserves its local data.

Apple documents seven-day Personal Team profiles, up to three apps per device, three registered devices and ten App IDs. Free development signing needs periodic Mac access for renewal, not during normal app use. [Apple Personal Team limits](https://developer.apple.com/help/account/basics/about-your-developer-account).

## Troubleshooting

| Symptom | Next action |
| --- | --- |
| Requires a development team | Select your actual Personal Team; check Apple Accounts sign-in and agreements. |
| Identifier unavailable | Choose a unique identifier for a new installation. Preserve the identifier of an existing app with valuable data. |
| Profile missing / phone excluded | Connect, unlock and pair the phone; allow registration/provisioning and check account/device limits and network access. |
| HealthKit entitlement mismatch | Keep HealthKit on the app target and let automatic signing recreate the profile for the correct team/identifier. Apple's [capability matrix](https://developer.apple.com/help/account/reference/supported-capabilities-ios) currently lists free HealthKit support. |
| codesign fails or waits | Respond to the Mac's Keychain prompt. Retry Command-R. Never disable signing for a physical installation. |
| Untrusted Developer | Trust your matching identity under VPN & Device Management; follow the phone's prompts. |
| Phone unavailable | Read Xcode's destination reason; check cable/trust, iOS 17+, platform components and Xcode support for that OS. |
| App stops opening after a week | Renew through Xcode with the same identifier; do not uninstall. |
| Health unavailable or blank | Unlock, check read switches and genuine samples on that day, allow Watch sync and refresh. |

## What has actually been verified


### October 19 update verification


### October 20 approved update
