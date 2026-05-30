// ============================================================
// AUTO-GENERATED FROM gtbi.manifest.yaml — DO NOT EDIT
// Regenerate: bun run generate (from packages/manifest)
// ============================================================

export interface ManifestLessonLink {
  moduleId: string;
  lessonSlug: string;
  displayName: string;
}

export const manifestLessonLinks: ManifestLessonLink[] = [
  {
    moduleId: "stack.agent_settings_backup",
    lessonSlug: "asb",
    displayName: "Agent Settings Backup",
  },
  {
    moduleId: "stack.cross_agent_session_resumer",
    lessonSlug: "casr",
    displayName: "Cross-Agent Session Resumer",
  },
  {
    moduleId: "stack.doodlestein_self_releaser",
    lessonSlug: "dsr",
    displayName: "Doodlestein Self-Releaser",
  },
  {
    moduleId: "stack.frankensearch",
    lessonSlug: "fsfs",
    displayName: "FrankenSearch",
  },
  {
    moduleId: "stack.pcr",
    lessonSlug: "pcr",
    displayName: "Post-Compact Reminder",
  },
  {
    moduleId: "stack.process_triage",
    lessonSlug: "pt",
    displayName: "Process Triage",
  },
  {
    moduleId: "stack.rch",
    lessonSlug: "rch",
    displayName: "Remote Compilation Helper",
  },
  {
    moduleId: "stack.storage_ballast_helper",
    lessonSlug: "sbh",
    displayName: "Storage Ballast Helper",
  },
];

/** Lookup lesson slug by module ID */
export const lessonSlugByModuleId: Record<string, string> = {
  "stack.agent_settings_backup": "asb",
  "stack.cross_agent_session_resumer": "casr",
  "stack.doodlestein_self_releaser": "dsr",
  "stack.frankensearch": "fsfs",
  "stack.pcr": "pcr",
  "stack.process_triage": "pt",
  "stack.rch": "rch",
  "stack.storage_ballast_helper": "sbh",
};
