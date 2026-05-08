import { describe, expect, test } from "bun:test";
import {
  calculateRequiredSpecs,
  getWorkloadProfile,
  validateVPSReadiness,
  type VPSReadinessResult,
} from "./vpsProviders";

function checkStatus(result: VPSReadinessResult, id: string) {
  return result.checks.find((check) => check.id === id)?.status;
}

describe("VPS capacity sizing", () => {
  test("keeps the wizard calculator aligned with the standard ACFS profile", () => {
    const standard = getWorkloadProfile("standard");
    const heavy = getWorkloadProfile("heavy");

    expect(calculateRequiredSpecs(10, standard, true)).toEqual({
      ramGB: 64,
      vCPU: 16,
      storageGB: 250,
    });
    expect(calculateRequiredSpecs(25, heavy, true)).toEqual({
      ramGB: 192,
      vCPU: 96,
      storageGB: 250,
    });
  });
});

describe("validateVPSReadiness", () => {
  test("supports a recommended provider plan, Ubuntu image, region, and target", () => {
    const result = validateVPSReadiness({
      providerId: "contabo",
      planName: "Cloud VPS 50",
      ubuntuVersion: "25.10",
      region: "us",
      targetAgents: 10,
      workloadId: "standard",
    });

    expect(result.status).toBe("supported");
    expect(result.provider?.name).toBe("Contabo");
    expect(result.plan?.name).toBe("Cloud VPS 50");
    expect(checkStatus(result, "capacity")).toBe("supported");
  });

  test("marks a budget plan as borderline when the target leaves little headroom", () => {
    const result = validateVPSReadiness({
      providerId: "contabo",
      planName: "Cloud VPS 40",
      ubuntuVersion: "24.04",
      region: "us",
      targetAgents: 10,
      workloadId: "standard",
    });

    expect(result.status).toBe("borderline");
    expect(checkStatus(result, "capacity")).toBe("borderline");
    expect(result.summary).toContain("Workable");
  });

  test("marks too-small capacity and old Ubuntu images as unsupported", () => {
    const result = validateVPSReadiness({
      providerId: "ovh",
      planName: "VPS-4",
      ubuntuVersion: "20.04",
      region: "us-east",
      targetAgents: 25,
      workloadId: "heavy",
    });

    expect(result.status).toBe("unsupported");
    expect(checkStatus(result, "capacity")).toBe("unsupported");
    expect(checkStatus(result, "os")).toBe("unsupported");
  });

  test("surfaces weak provider regions as advisory warnings", () => {
    const result = validateVPSReadiness({
      providerId: "contabo",
      planName: "Cloud VPS 50",
      ubuntuVersion: "25.10",
      region: "asia",
      targetAgents: 10,
      workloadId: "standard",
    });

    expect(result.status).toBe("borderline");
    expect(checkStatus(result, "region")).toBe("borderline");
  });

  test("keeps unknown providers advisory instead of pretending they are safe", () => {
    const result = validateVPSReadiness({
      providerId: "other",
      planName: "custom plan",
      ubuntuVersion: "25.10",
      region: "not-listed",
      targetAgents: 10,
      workloadId: "standard",
    });

    expect(result.status).toBe("unknown");
    expect(result.provider).toBeNull();
    expect(result.plan).toBeNull();
    expect(checkStatus(result, "provider")).toBe("unknown");
    expect(checkStatus(result, "plan")).toBe("unknown");
  });

  test("keeps unknown plans advisory even for a known provider", () => {
    const result = validateVPSReadiness({
      providerId: "contabo",
      planName: "Cloud VPS 10",
      ubuntuVersion: "25.10",
      region: "us",
      targetAgents: 10,
      workloadId: "standard",
    });

    expect(result.status).toBe("unknown");
    expect(result.provider?.name).toBe("Contabo");
    expect(result.plan).toBeNull();
    expect(checkStatus(result, "plan")).toBe("unknown");
  });
});
