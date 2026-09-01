import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

function read(path) {
  return fs.readFileSync(path, 'utf8');
}

function assertContract(condition, message) {
  if (!condition) throw new Error(message);
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function filesUnder(root, extensions) {
  const result = [];
  const visit = (directory) => {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const entryPath = path.join(directory, entry.name);
      if (entry.isDirectory()) {
        visit(entryPath);
      } else if (entry.isFile() && extensions.has(path.extname(entry.name))) {
        result.push(entryPath);
      }
    }
  };
  visit(root);
  return result;
}

const manifest = read('android/app/src/main/AndroidManifest.xml');
const appGradle = read('android/app/build.gradle.kts');
const settingsGradle = read('android/settings.gradle.kts');
const gitignore = read('.gitignore');
const monetization = [
  'lib/src/features/monetization/monetization.dart',
  ...filesUnder('lib/src/features/monetization/src', new Set(['.dart'])),
]
  .map(read)
  .join('\n');
const adRuntime = read('lib/src/features/monetization/ad_runtime.dart');
const adRetry = read('lib/src/features/monetization/ad_retry_policy.dart');
const adCache = read('lib/src/features/monetization/ad_cache.dart');
const ssv = read('supabase/functions/admob-ssv-handler/index.ts');
const authoritativePointsMigration = read(
  'supabase/migrations/20260821124930_initial_schema.sql',
);
const deletionClient = read('download-site/account-deletion.js');
const flutterDeletionClient = read(
  'lib/src/features/auth/data/supabase_auth_repository.dart',
);
const deletionFunction = read('supabase/functions/delete-account/index.ts');
const deletionStatusFunction = read(
  'supabase/functions/account-deletion-status/index.ts',
);
const serviceWorker = read('download-site/sw.js');

assertContract(
  /com\.google\.android\.gms\.ads\.APPLICATION_ID/.test(manifest),
  'AdMob application metadata is missing.',
);
assertContract(
  /\$\{admobAppId\}/.test(manifest),
  'The source Android manifest must use the admobAppId placeholder.',
);
assertContract(
  /ca-app-pub-5274007212820203~7167645746/.test(appGradle),
  'The production Gradle configuration must declare the production AdMob app ID.',
);
assertContract(
  (manifest.match(/com\.google\.android\.gms\.ads\.APPLICATION_ID/g) ?? [])
    .length === 1,
  'The source manifest must contain exactly one AdMob application metadata entry.',
);
assertContract(
  /android:allowBackup\s*=\s*["']false["']/.test(manifest),
  'Android backup must remain explicitly disabled.',
);
assertContract(!/ACCESS_FINE_LOCATION/.test(manifest), 'Fine location is forbidden.');
assertContract(
  !/ACCESS_BACKGROUND_LOCATION/.test(manifest),
  'Background location is forbidden.',
);
assertContract(/targetSdk\s*=\s*36/.test(appGradle), 'targetSdk must remain API 36.');
assertContract(/compileSdk\s*=\s*37/.test(appGradle), 'compileSdk must remain API 37.');

const gradleSources = `${appGradle}\n${settingsGradle}`;
assertContract(
  !/firebase-analytics|firebase-bom/i.test(gradleSources),
  'Direct Firebase Analytics dependencies are forbidden.',
);
assertContract(
  !/com\.google\.gms\.google-services/.test(gradleSources),
  'The Google Services Gradle plugin must not be applied.',
);
assertContract(
  /android\/app\/google-services\.json/.test(gitignore),
  'Real google-services.json files must remain ignored.',
);
let trackedFiles = [];
try {
  trackedFiles = execFileSync('git', ['ls-files', '--'], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'ignore'],
  })
    .split(/\r?\n/)
    .filter(Boolean);
} catch {
  // Gracefully fallback when not executing within a git working tree
}
const trackedGoogleServices = trackedFiles.filter((file) =>
  /(^|\/)google-services\.json$/i.test(file),
);
assertContract(
  trackedGoogleServices.length === 0,
  `Tracked google-services.json files are forbidden: ${trackedGoogleServices.join(', ')}`,
);
assertContract(
  !fs.existsSync('android/app/google-services.json.example'),
  'The obsolete google-services.json.example must not be tracked.',
);

const rewardedId = 'ca-app-pub-5274007212820203/4541482404';
const rewardedInterstitialId = 'ca-app-pub-5274007212820203/7295784043';
for (const [label, source] of [
  ['Flutter client', monetization],
  ['AdMob SSV function', ssv],
  ['authoritative points migration', authoritativePointsMigration],
]) {
  assertContract(source.includes(rewardedId), `${label} rewarded ID differs.`);
  assertContract(
    source.includes(rewardedInterstitialId),
    `${label} rewarded-interstitial ID differs.`,
  );
}
assertContract(
  /rewardAmount:\s*1/.test(ssv) && /rewardAmount:\s*2/.test(ssv),
  'SSV reward amounts must remain 1 and 2.',
);
assertContract(
  /p_reward_type\s*=\s*'rewarded_ad'\s+then\s+1\s+else\s+2/i.test(
    authoritativePointsMigration,
  ),
  'Database reward amounts must remain 1 and 2.',
);
const adUnitsStart = monetization.indexOf('class OwntendAdUnits');
const adUnitsEnd = monetization.indexOf('class OwntendAdsService');
assertContract(
  adUnitsStart >= 0 && adUnitsEnd > adUnitsStart,
  'The Owntend ad-unit mapping could not be isolated.',
);
const adUnits = monetization.slice(adUnitsStart, adUnitsEnd);
const approvedDemoIds = [
  'ca-app-pub-3940256099942544/2247696110',
  'ca-app-pub-3940256099942544/1033173712',
  'ca-app-pub-3940256099942544/5224354917',
  'ca-app-pub-3940256099942544/5354046379',
];
const configuredDemoIds = [
  ...adUnits.matchAll(/ca-app-pub-3940256099942544\/\d+/g),
].map((match) => match[0]);
assertContract(
  configuredDemoIds.length === approvedDemoIds.length &&
    approvedDemoIds.every((id) => configuredDemoIds.includes(id)),
  'Non-production ads must use exactly the four approved Google sample IDs.',
);
const productionAdUnitIds = [
  'ca-app-pub-5274007212820203/8393243294',
  'ca-app-pub-5274007212820203/7543196051',
  'ca-app-pub-5274007212820203/3851363056',
  rewardedId,
  rewardedInterstitialId,
];
for (const id of productionAdUnitIds) {
  assertContract(adUnits.includes(id), `Production ad-unit mapping is missing ${id}.`);
}
assertContract(
  new RegExp(
    `if\\s*\\(\\s*!production\\s*\\)\\s*return\\s*['"]${escapeRegExp(approvedDemoIds[0])}['"]`,
  ).test(adUnits),
  'The non-production native mapping must return the approved native sample ID.',
);
for (const [getter, productionId, demoId] of [
  ['interstitial', productionAdUnitIds[2], approvedDemoIds[1]],
  ['rewarded', rewardedId, approvedDemoIds[2]],
  ['rewardedInterstitial', rewardedInterstitialId, approvedDemoIds[3]],
]) {
  assertContract(
    new RegExp(
      `String\\s+get\\s+${getter}\\s*=>\\s*production\\s*\\?\\s*['"]${escapeRegExp(productionId)}['"]\\s*:\\s*['"]${escapeRegExp(demoId)}['"]`,
      's',
    ).test(adUnits),
    `${getter} must map production and non-production to their approved IDs.`,
  );
}

assertContract(
  /class AdRuntimeEligibility/.test(adRuntime),
  'The central ad runtime eligibility contract is missing.',
);
assertContract(
  /consentUpdated/.test(adRuntime) && /appResumed/.test(adRuntime),
  'Ad runtime must gate on refreshed consent and resumed lifecycle.',
);
assertContract(
  /class AdRetryPolicy/.test(adRetry) && /AdRetryDecision\.dormant/.test(adRetry),
  'Bounded retry and dormancy contracts are missing.',
);
assertContract(
  /AdLoadFailureKind\.network\s*=>\s*4/.test(adRetry) &&
    /failedAttempt\s*>\s*maxAutomaticRetries/.test(adRetry) &&
    /baseSeconds\s*=\s*\[2,\s*8,\s*30,\s*60\]/.test(adRetry),
  'Network ads must have four automatic retries at 2, 8, 30, and 60 seconds.',
);
assertContract(
  /Duration\(minutes:\s*55\)/.test(adCache),
  'The 55-minute ad cache limit is missing.',
);
assertContract(
  /class FullScreenAdGate/.test(adCache),
  'Fullscreen ad serialization is missing.',
);

const distributableFiles = [
  ...filesUnder('lib', new Set(['.dart'])),
  ...filesUnder(
    'android/app/src',
    new Set(['.java', '.json', '.kt', '.properties', '.xml']),
  ),
  ...filesUnder('download-site', new Set(['.css', '.html', '.js', '.json'])),
];
for (const file of distributableFiles) {
  const source = read(file);
  assertContract(
    !/SUPABASE_(?:SERVICE_ROLE|SERVICE)_KEY|\bserviceRole(?:Key|Token|Secret)\b|\bservice_role_key\b/i.test(
      source,
    ),
    `A service-role credential binding exists in distributable source: ${file}`,
  );
  assertContract(
    !/["']sb_secret_[A-Za-z0-9_-]{8,}["']/.test(source),
    `A Supabase secret key literal exists in distributable source: ${file}`,
  );
  for (const match of source.matchAll(
    /eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/g,
  )) {
    try {
      const payload = JSON.parse(
        Buffer.from(match[0].split('.')[1], 'base64url').toString('utf8'),
      );
      assertContract(
        payload.role !== 'service_role',
        `A service-role JWT literal exists in distributable source: ${file}`,
      );
    } catch (error) {
      if (error instanceof SyntaxError) continue;
      throw error;
    }
  }
}
assertContract(
  !/setTimeout\s*\(/.test(deletionClient),
  'Account deletion must never be simulated with a timer.',
);
assertContract(
  /code_challenge_method/.test(deletionClient) &&
    /functions\/v1\/delete-account/.test(deletionClient),
  'The deletion client must use PKCE and the protected Edge Function.',
);
assertContract(
  !/localStorage/.test(deletionClient) &&
    /sessionStorage\.setItem\(PKCE_STORAGE_KEY, pkce\.verifier\)/.test(deletionClient) &&
    /saveAccountDeletionOperation/.test(deletionClient) &&
    !/sessionStorage\.setItem\([^\n]*(access|refresh)[_-]?token/i.test(deletionClient),
  'Session storage may retain PKCE and deletion-recovery material, but tokens must remain in memory.',
);
for (const [label, source] of [
  ['browser deletion producer', deletionClient],
  ['Flutter deletion producer', flutterDeletionClient],
]) {
  assertContract(
    source.includes('confirmation') && source.includes('recovery_key'),
    `${label} must send confirmation and recovery_key.`,
  );
  assertContract(
    source.includes('account-deletion-status') &&
      source.includes('expected_user_id'),
    `${label} must reconcile with recovery_key and expected_user_id.`,
  );
}
for (const [label, source] of [
  ['delete-account', deletionFunction],
  ['account-deletion-status', deletionStatusFunction],
]) {
  assertContract(
    /\^\[A-Za-z0-9_-\]\{43\}\$/.test(source) &&
      /decodeBase64Url\([^)]*\)\.length\s*(?:===|!==)\s*32/.test(source),
    `${label} must enforce a 43-character recovery key that decodes to 32 bytes.`,
  );
}
assertContract(
  (/https:\/\/owntend\.app/.test(deletionFunction) || /https:\/\/zuhak5\.github\.io/.test(deletionFunction)) &&
    /http:\/\/localhost:4173/.test(deletionFunction),
  'The deletion function exact-origin CORS allowlist is missing.',
);
assertContract(
  /networkOnlyAccountDeletionNavigation/.test(serviceWorker) &&
    /event\.respondWith\(networkOnlyAccountDeletionNavigation\(request\)\)/.test(
      serviceWorker,
    ),
  'Account-deletion navigation must bypass VersionDeck offline caching.',
);

console.log('Google, ads, backend, and Android static contracts verified.');
