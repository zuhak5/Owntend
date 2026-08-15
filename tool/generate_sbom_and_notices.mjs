import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  loadDenoDependencies,
  loadNpmDependencies,
  loadPubDependencies,
  validateDependencies,
} from './dependency_review_policy.mjs';

const repositoryRoot = fileURLToPath(new URL('../', import.meta.url));

const STANDARD_LICENSE_TEXTS = Object.freeze({
  'MIT': `The MIT License (MIT)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.`,

  'BSD-3-Clause': `Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.`,

  'BSD-2-Clause': `Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.`,

  'Apache-2.0': `                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.
      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.
      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.
      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity.
      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.
      "Source" form shall mean the preferred form for making modifications.
      "Object" form shall mean any form resulting from mechanical transformation.
      "Work" shall mean the work of authorship made available under the License.
      "Derivative Works" shall mean any work based upon (or derived from) the Work.
      "Contribution" shall mean any work of authorship intentionally submitted to
      Licensor for inclusion in the Work.
      "Contributor" shall mean Licensor and any individual or Legal Entity on
      behalf of whom a Contribution has been received by Licensor.

   2. Grant of Copyright License. Subject to the terms and conditions of this
      License, each Contributor hereby grants to You a perpetual, worldwide,
      non-exclusive, no-charge, royalty-free, irrevocable copyright license to
      reproduce, prepare Derivative Works of, publicly display, publicly perform,
      sublicense, and distribute the Work and such Derivative Works in Source or
      Object form.

   3. Grant of Patent License. Subject to the terms and conditions of this
      License, each Contributor hereby grants to You a perpetual, worldwide,
      non-exclusive, no-charge, royalty-free, irrevocable patent license to
      make, have made, use, offer to sell, sell, import, and otherwise transfer
      the Work.

   4. Redistribution. You may reproduce and distribute copies of the Work or
      Derivative Works thereof in any medium, with or without modifications,
      and in Source or Object form, provided that You meet the following conditions:
      (a) You must give any other recipients of the Work or Derivative Works a
          copy of this License; and
      (b) You must cause any modified files to carry prominent notices stating
          that You changed the files; and
      (c) You must retain, in the Source form of any Derivative Works that You
          distribute, all copyright, patent, trademark, and attribution notices; and
      (d) If the Work includes a "NOTICE" text file as part of its distribution,
          then any Derivative Works that You distribute must include a readable copy
          of the attribution notices contained within such NOTICE file.

   5. Submission of Contributions. Unless You explicitly state otherwise, any
      Contribution intentionally submitted for inclusion in the Work by You to the
      Licensor shall be under the terms and conditions of this License, without any
      additional terms or conditions.

   6. Trademarks. This License does not grant permission to use the trade names,
      trademarks, service marks, or product names of the Licensor, except as
      required for reasonable and customary use in describing the origin of the Work.

   7. Disclaimer of Warranty. Unless required by applicable law or agreed to in
      writing, Licensor provides the Work (and each Contributor provides its
      Contributions) on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF
      ANY KIND, either express or implied.

   8. Limitation of Liability. In no event and under no legal theory shall any
      Contributor be liable to You for damages, including any direct, indirect,
      special, incidental, or consequential damages of any character arising as
      a result of this License or out of the use or inability to use the Work.

   9. Accepting Warranty or Additional Liability. While redistributing the Work
      or Derivative Works thereof, You may choose to offer, and charge a fee for,
      acceptance of support, warranty, indemnity, or other liability obligations.`,

  'ISC': `ISC License

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.`,

  '0BSD': `Zero-Clause BSD (0BSD)

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
PERFORMANCE OF THIS SOFTWARE.`,
});

export function generateSpdxSbom({
  versionName = '1.0.0',
  buildNumber = '1',
  sourceSha = 'HEAD',
  pubPackages = [],
  npmPackages = [],
  denoPackages = [],
  createdTimestamp = null,
} = {}) {
  const created = createdTimestamp || new Date().toISOString();
  const docId = `SPDXRef-DOCUMENT`;
  const namespace = `https://owntend.app/spdxdocs/owntend-${versionName}-build.${buildNumber}-${crypto
    .createHash('sha256')
    .update(`${versionName}+${buildNumber}-${sourceSha}`)
    .digest('hex')
    .substring(0, 16)}`;

  const allPackages = [
    ...pubPackages.map(p => ({ ...p, ecosystemPrefix: 'pub' })),
    ...npmPackages.map(p => ({ ...p, ecosystemPrefix: 'npm' })),
    ...denoPackages.map(p => ({ ...p, ecosystemPrefix: 'deno' })),
  ];

  // Deterministically sort packages
  allPackages.sort((a, b) => {
    const keyA = `${a.ecosystemPrefix}:${a.name}@${a.version}`;
    const keyB = `${b.ecosystemPrefix}:${b.name}@${b.version}`;
    return keyA.localeCompare(keyB);
  });

  const spdxPackages = allPackages.map(pkg => {
    const sanitizedName = pkg.name.replace(/[^a-zA-Z0-9.-]/g, '-');
    const sanitizedVer = pkg.version.replace(/[^a-zA-Z0-9.-]/g, '-');
    const spdxId = `SPDXRef-Package-${pkg.ecosystemPrefix}-${sanitizedName}-${sanitizedVer}`;

    const checksums = [];
    if (pkg.sha256) {
      checksums.push({
        algorithm: 'SHA256',
        checksumValue: pkg.sha256.toLowerCase(),
      });
    } else if (pkg.integrity && pkg.integrity.startsWith('sha512-')) {
      const b64 = pkg.integrity.substring(7);
      const hex = Buffer.from(b64, 'base64').toString('hex');
      checksums.push({
        algorithm: 'SHA512',
        checksumValue: hex.toLowerCase(),
      });
    }

    const downloadLocation = pkg.url || `https://pub.dev/packages/${pkg.name}`;

    return {
      SPDXID: spdxId,
      name: pkg.name,
      versionInfo: pkg.version,
      downloadLocation,
      filesAnalyzed: false,
      licenseConcluded: pkg.license || 'NOASSERTION',
      licenseDeclared: pkg.license || 'NOASSERTION',
      copyrightText: 'NOASSERTION',
      supplier: `Organization: ${pkg.ecosystem === 'pub' ? 'Dart/Flutter Ecosystem' : pkg.ecosystem === 'npm' ? 'Node/npm Ecosystem' : 'Deno/JSR Ecosystem'}`,
      checksums: checksums.length > 0 ? checksums : undefined,
      externalRefs: [
        {
          referenceCategory: 'PACKAGE-MANAGER',
          referenceType: 'purl',
          referenceLocator: pkg.purl,
        },
      ],
    };
  });

  const relationships = spdxPackages.map(pkg => ({
    spdxElementId: docId,
    relatedSpdxElement: pkg.SPDXID,
    relationshipType: 'DESCRIBES',
  }));

  return {
    spdxVersion: 'SPDX-2.3',
    dataLicense: 'CC0-1.0',
    SPDXID: docId,
    name: `Owntend-Dependency-SBOM-${versionName}+${buildNumber}`,
    documentNamespace: namespace,
    creationInfo: {
      created,
      creators: [
        'Tool: Owntend-SBOM-Generator-1.0.0',
        'Organization: Owntend',
      ],
    },
    packages: spdxPackages,
    relationships,
  };
}

export function generateThirdPartyNotices({
  versionName = '1.0.0',
  buildNumber = '1',
  pubPackages = [],
  npmPackages = [],
  denoPackages = [],
} = {}) {
  const lines = [
    '# Third-Party Dependency Notices',
    '',
    `**Product:** Owntend Android Application`,
    `**Version:** ${versionName} (Build ${buildNumber})`,
    `**Generated:** ${new Date().toISOString()}`,
    '',
    '> Owntend uses and redistributes open-source software packages under their respective upstream licenses.',
    '> This document contains third-party notices, attribution statements, and full license texts for all direct and',
    '> transitive dependencies included in or used by the Owntend application and its tooling.',
    '',
    '## Table of Contents',
    '',
    '1. [Dart and Flutter Dependencies](#1-dart-and-flutter-dependencies)',
    '2. [Node.js Build and Tooling Dependencies](#2-nodejs-build-and-tooling-dependencies)',
    '3. [Deno and Supabase Edge Function Dependencies](#3-deno-and-supabase-edge-function-dependencies)',
    '4. [Standard License Texts](#4-standard-license-texts)',
    '',
    '---',
    '',
    '## 1. Dart and Flutter Dependencies',
    '',
    `Total resolved packages: **${pubPackages.length}**`,
    '',
    '| Package | Version | Type | License | Upstream Link |',
    '| :--- | :--- | :--- | :--- | :--- |',
  ];

  for (const pkg of pubPackages) {
    lines.push(
      `| \`${pkg.name}\` | \`${pkg.version}\` | ${pkg.dependencyType} | ${pkg.license} | [pub.dev/${pkg.name}](https://pub.dev/packages/${pkg.name}) |`
    );
  }

  lines.push(
    '',
    '---',
    '',
    '## 2. Node.js Build and Tooling Dependencies',
    '',
    `Total resolved packages: **${npmPackages.length}**`,
    '',
    '| Package | Version | Type | License | Registry Link |',
    '| :--- | :--- | :--- | :--- | :--- |'
  );

  for (const pkg of npmPackages) {
    lines.push(
      `| \`${pkg.name}\` | \`${pkg.version}\` | ${pkg.dependencyType} | ${pkg.license} | [npmjs.com/package/${pkg.name}](https://www.npmjs.com/package/${pkg.name}) |`
    );
  }

  lines.push(
    '',
    '---',
    '',
    '## 3. Deno and Supabase Edge Function Dependencies',
    '',
    `Total resolved specifiers: **${denoPackages.length}**`,
    '',
    '| Package | Version | Source | License | Upstream Link |',
    '| :--- | :--- | :--- | :--- | :--- |'
  );

  for (const pkg of denoPackages) {
    lines.push(
      `| \`${pkg.name}\` | \`${pkg.version}\` | ${pkg.source} | ${pkg.license} | [${pkg.url}](${pkg.url}) |`
    );
  }

  lines.push(
    '',
    '---',
    '',
    '## 4. Standard License Texts',
    '',
    'The dependencies listed above are licensed under one or more of the following standard open-source licenses.',
    ''
  );

  for (const [name, text] of Object.entries(STANDARD_LICENSE_TEXTS)) {
    lines.push(
      `### ${name}`,
      '',
      '```text',
      text,
      '```',
      ''
    );
  }

  return lines.join('\n');
}

export async function generateReleaseArtifacts({
  outputDirectory = path.join(repositoryRoot, 'release', 'apk-evidence'),
  versionName = '1.0.0',
  buildNumber = '1',
  sourceSha = 'HEAD',
  rootDir = repositoryRoot,
} = {}) {
  // Validate policy first
  const policyResult = await validateDependencies(rootDir);
  if (!policyResult.valid) {
    throw new Error(
      `Cannot generate SBOM and notices: dependency policy validation failed with ${policyResult.errors.length} error(s):\n${policyResult.errors.join('\n')}`
    );
  }

  const [pubPackages, npmPackages, denoPackages] = await Promise.all([
    loadPubDependencies(rootDir),
    loadNpmDependencies(rootDir),
    loadDenoDependencies(rootDir),
  ]);

  await fs.mkdir(outputDirectory, { recursive: true });

  // Generate SBOM
  const sbomData = generateSpdxSbom({
    versionName,
    buildNumber,
    sourceSha,
    pubPackages,
    npmPackages,
    denoPackages,
  });

  const sbomContent = JSON.stringify(sbomData, null, 2);
  const sbomPath = path.join(outputDirectory, 'sbom.spdx.json');
  await fs.writeFile(sbomPath, sbomContent, 'utf8');

  const sbomSha256 = crypto.createHash('sha256').update(sbomContent).digest('hex').toLowerCase();

  // Generate Third-Party Notices
  const noticesContent = generateThirdPartyNotices({
    versionName,
    buildNumber,
    pubPackages,
    npmPackages,
    denoPackages,
  });

  const noticesPath = path.join(outputDirectory, 'THIRD_PARTY_NOTICES.md');
  await fs.writeFile(noticesPath, noticesContent, 'utf8');

  const noticesSha256 = crypto.createHash('sha256').update(noticesContent).digest('hex').toLowerCase();

  return {
    sbomPath,
    sbomSha256,
    sbomPackageCount: sbomData.packages.length,
    noticesPath,
    noticesSha256,
    pubCount: pubPackages.length,
    npmCount: npmPackages.length,
    denoCount: denoPackages.length,
  };
}

// CLI entrypoint
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  let outputDirectory = path.join(repositoryRoot, 'release', 'apk-evidence');
  let versionName = '1.0.0';
  let buildNumber = '1';
  let sourceSha = process.env.SOURCE_SHA || 'HEAD';

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--output-directory' && args[i + 1]) {
      outputDirectory = path.resolve(args[++i]);
    } else if (args[i] === '--version-name' && args[i + 1]) {
      versionName = args[++i];
    } else if (args[i] === '--build-number' && args[i + 1]) {
      buildNumber = args[++i];
    } else if (args[i] === '--source-sha' && args[i + 1]) {
      sourceSha = args[++i];
    }
  }

  const result = await generateReleaseArtifacts({
    outputDirectory,
    versionName,
    buildNumber,
    sourceSha,
  });

  console.log(`Generated SBOM: ${result.sbomPath} (SHA256: ${result.sbomSha256}, ${result.sbomPackageCount} packages)`);
  console.log(`Generated Notices: ${result.noticesPath} (SHA256: ${result.noticesSha256})`);
}
