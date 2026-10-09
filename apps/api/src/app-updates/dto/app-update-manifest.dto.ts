export type AppUpdateManifestDto =
  | {
      updateAvailable: false;
    }
  | {
      updateAvailable: true;
      version: string;
      buildNumber: number;
      fileName: string;
      fileSize: number;
      sha256: string;
      downloadUrl: string;
      mandatory: boolean;
      minimumSupportedBuild: number | null;
      releaseNotes: unknown[];
      publishedAt: string;
    };
