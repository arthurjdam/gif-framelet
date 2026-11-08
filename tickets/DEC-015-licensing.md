# DEC-015: Project license and gifski AGPL position

**Type:** Decision · **Status:** Backlog. Owner only, not for an engineer.

- The repo has no `LICENSE` for Framelet itself.
- gifski is AGPL-3.0 (with a commercial option). RELEASING.md already says to
  resolve this before distribution. Bundling an AGPL binary in a distributed app likely
  means releasing Framelet under an AGPL-compatible license or buying the
  commercial license.

**Decision needed:** Pick the Framelet license (e.g. AGPL-3.0), or buy a gifski
commercial license, or swap encoders. Then add `LICENSE`, and update THIRD_PARTY.md and the About credits (FEAT-010).
