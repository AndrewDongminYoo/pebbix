#!/bin/sh
# Prints the AdMob application ID the iOS build should carry. The Runner target's
# "Set AdMob application ID" build phase writes it into the built Info.plist.
#
# The Mobile Ads SDK reads the ID at startup, and ad units only serve under the app that
# owns them. Only Release-production may carry the real ID, and only together with the two
# unit-ID --dart-define flags, so the app and its units come from one AdMob account.
# android/app/build.gradle.kts applies the same rule to the Android build; keep the two in step.
set -eu

readonly google_sample_app_id='ca-app-pub-3940256099942544~1458002511'

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

if [ "${CONFIGURATION:-}" != 'Release-production' ]; then
	printf '%s\n' "${google_sample_app_id}"
	exit 0
fi

# flutter_tools exports every --dart-define as one comma-separated list of base64 entries.
app_id=''
rewarded=''
interstitial=''
set -f
old_ifs=${IFS}
IFS=','
for encoded in ${DART_DEFINES:-}; do
	# base64's decode flag differs between GNU coreutils and macOS releases. GNU takes --decode;
	# every macOS base64 takes -D, so that is the fallback when --decode is refused.
	define=$(printf '%s' "${encoded}" | base64 --decode 2>/dev/null ||
		printf '%s' "${encoded}" | base64 -D) ||
		fail "DART_DEFINES holds an entry that is not base64: ${encoded}"
	case ${define} in
	ADMOB_APP_ID=*) app_id=${define#ADMOB_APP_ID=} ;;
	ADMOB_REWARDED_AD_UNIT_ID=*) rewarded=${define#ADMOB_REWARDED_AD_UNIT_ID=} ;;
	ADMOB_INTERSTITIAL_AD_UNIT_ID=*) interstitial=${define#ADMOB_INTERSTITIAL_AD_UNIT_ID=} ;;
	*) ;;
	esac
done
IFS=${old_ifs}
set +f

# No AdMob defines at all keeps the sample ID, which is what the release builds before
# the account existed shipped. Anything in between is a half-configured release.
if [ -z "${app_id}${rewarded}${interstitial}" ]; then
	printf '%s\n' "${google_sample_app_id}"
	exit 0
fi

missing=''
for pair in "ADMOB_APP_ID=${app_id}" "ADMOB_REWARDED_AD_UNIT_ID=${rewarded}" \
	"ADMOB_INTERSTITIAL_AD_UNIT_ID=${interstitial}"; do
	[ -n "${pair#*=}" ] || missing="${missing:+${missing}, }${pair%%=*}"
done
[ -z "${missing}" ] || fail "A production release needs all AdMob dart-defines; missing: ${missing}."

printf '%s\n' "${app_id}" | grep -Eq '^ca-app-pub-[0-9]{16}~[0-9]{10}$' ||
	fail "ADMOB_APP_ID is not an AdMob application ID: ${app_id}"
for pair in "ADMOB_REWARDED_AD_UNIT_ID=${rewarded}" "ADMOB_INTERSTITIAL_AD_UNIT_ID=${interstitial}"; do
	printf '%s\n' "${pair#*=}" | grep -Eq '^ca-app-pub-[0-9]{16}/[0-9]{10}$' ||
		fail "${pair%%=*} is not an AdMob ad unit ID: ${pair#*=}"
done
publisher=${app_id%%~*}
[ "${publisher}" != "${google_sample_app_id%%~*}" ] ||
	fail "ADMOB_APP_ID is Google's sample publisher, not this app's AdMob account."

foreign=''
for pair in "ADMOB_REWARDED_AD_UNIT_ID=${rewarded}" "ADMOB_INTERSTITIAL_AD_UNIT_ID=${interstitial}"; do
	case ${pair#*=} in
	"${publisher}/"*) ;;
	*) foreign="${foreign:+${foreign}, }${pair%%=*}" ;;
	esac
done
[ -z "${foreign}" ] || fail "${foreign} must belong to the ADMOB_APP_ID publisher ${publisher}."

printf '%s\n' "${app_id}"
