// =============================================================================
// tensorrail_enclosure.scad
// Parametric Enclosure for TensorRail-Mini Carrier Board
// TensorRail-Mini · ECP5 Carrier Board Proof-of-Concept
//
// Board: 80 mm × 50 mm, 1.6 mm thick
// Module clearance: 16 mm above PCB top surface (OrangeCrab 85F ≈ 12 mm tall)
//
// Connectors on the carrier board (all cutouts included):
//   J1  USB-C         — LEFT  edge, centred at Y = 25 mm
//   J2  JTAG 2×5      — TOP   edge, centred at X = 43 mm
//   J3  40-pin header — RIGHT edge, full-height slot
//
// Render targets (set PART variable before rendering):
//   PART = "assembly"  — base + lid together (default view)
//   PART = "base"      — bottom tray only  → base.stl
//   PART = "lid"       — top plate only    → lid.stl
//   PART = "exploded"  — assembly with lid raised 20 mm
//
// OpenSCAD render commands:
//   openscad mechanical/tensorrail_enclosure.scad
//   openscad -D 'PART="base"'     -o mechanical/base.stl     mechanical/tensorrail_enclosure.scad
//   openscad -D 'PART="lid"'      -o mechanical/lid.stl      mechanical/tensorrail_enclosure.scad
//   openscad -D 'PART="exploded"' -o mechanical/exploded.stl mechanical/tensorrail_enclosure.scad
//
// Suggested print settings:
//   Material      : PETG (better heat tolerance than PLA near electronics)
//   Layer height  : 0.2 mm
//   Infill        : 20 % gyroid
//   Perimeters    : 3
//   Supports      : none required (base opens upward; lid is flat)
// =============================================================================

/* [Render target] */
PART = "assembly";   // "assembly" | "base" | "lid" | "exploded"

// ── PCB dimensions ────────────────────────────────────────────────────────────
/* [PCB] */
PCB_L = 80.0;   // Board length  (X axis)
PCB_W = 50.0;   // Board width   (Y axis)
PCB_T =  1.6;   // Board thickness

// ── Enclosure geometry ────────────────────────────────────────────────────────
/* [Enclosure] */
WALL       = 2.5;   // Outer wall thickness
LID_T      = 3.0;   // Lid plate thickness
STANDOFF_H = 4.0;   // Height of PCB standoffs above base floor
COMP_CLR   = 16.0;  // Component clearance above PCB top surface
                    // (covers OrangeCrab 85F module ≈ 12 mm)
CORNER_R   = 3.0;   // Corner rounding radius
FLOOR_T    = WALL;  // Base floor thickness (same as wall)

// ── Derived dimensions ────────────────────────────────────────────────────────
INNER_L = PCB_L + 2.0;   // 1 mm clearance each side in X
INNER_W = PCB_W + 2.0;   // 1 mm clearance each side in Y
INNER_H = STANDOFF_H + PCB_T + COMP_CLR;   // Internal cavity height

OUT_L = INNER_L + 2 * WALL;   // Outer length
OUT_W = INNER_W + 2 * WALL;   // Outer width
OUT_H = INNER_H + FLOOR_T;    // Outer base height (without lid)

// PCB origin inside the enclosure (bottom-left of PCB footprint)
PCB_OX = WALL + 1;   // X offset of PCB (0,0) from enclosure (0,0)
PCB_OY = WALL + 1;   // Y offset of PCB (0,0) from enclosure (0,0)
PCB_OZ = FLOOR_T + STANDOFF_H;  // Z of PCB bottom surface

// ── Fasteners ─────────────────────────────────────────────────────────────────
/* [Fasteners] */
M3_CLEAR  = 3.4;   // M3 bolt clearance hole diameter
M3_INSERT = 4.2;   // M3 heat-set insert OD (M3×4 mm, 5 mm OD type)
BOSS_OD   = 7.0;   // Standoff boss outer diameter

// ── PCB mounting hole positions (PCB-relative, matching hardware/tensorrail_mini.kicad_pcb)
MH = [[3, 3], [77, 3], [3, 47], [77, 47]];   // [X, Y] in mm from PCB corner

// ── Connector cutout parameters ───────────────────────────────────────────────
/* [Connectors] */

// J1: USB-C GCT USB4135 — LEFT edge of PCB, centred at Y=25 mm on board
// Body: 9 mm wide × 4.5 mm tall; add 1 mm each side for tolerance
USBC_Y      = 25.0;   // PCB-relative Y centre
USBC_CUT_W  = 11.5;   // Cutout width  (connector body + tolerance)
USBC_CUT_H  =  6.0;   // Cutout height (from PCB surface upward)
// Z centre = PCB top surface + 1.5 mm (USB-C body sits mostly above PCB)
USBC_CUT_Z  = PCB_OZ + PCB_T + 1.5;

// J2: JTAG 2×5 1.27 mm IDC — TOP edge of PCB, centred at X=43 mm
JTAG_X      = 43.0;   // PCB-relative X centre
JTAG_CUT_W  = 14.0;   // Cutout width  (10-pin IDC body + tolerance)
JTAG_CUT_H  = 11.0;   // Cutout height (connector body height)
JTAG_CUT_Z  = PCB_OZ;  // Starts at PCB surface

// J3: 40-pin 2×20 2.54 mm expansion header — RIGHT edge of PCB
// Header spans Y = 0.87 mm to Y = 49.13 mm (centred on board at Y=25)
EXP_CUT_W  = 52.0;   // Full span of header + tolerance
EXP_CUT_H  = 12.0;   // Header body height
EXP_CUT_Z  = PCB_OZ; // Starts at PCB surface

// ── Ventilation slots ─────────────────────────────────────────────────────────
/* [Ventilation] */
VENT_W      = 12.0;   // Individual slot width
VENT_H      =  4.0;   // Individual slot height
VENT_PITCH  = 18.0;   // Slot centre-to-centre pitch
VENT_COUNT  = 3;      // Number of slots per side wall
VENT_MARGIN =  8.0;   // Distance from bottom of first slot to front edge
// Vertical position: near the top of the side walls, in the component-height zone
VENT_Z      = FLOOR_T + STANDOFF_H + PCB_T + 4.0;

// ── LED light-pipe holes in lid ───────────────────────────────────────────────
/* [LEDs] */
LED_D   = 3.2;   // Light-pipe hole diameter
// LED positions (PCB-relative X, Y) — matches D2–D5 in tensorrail_mini.kicad_pcb
LED_POS = [[70, 38], [70, 40.5], [70, 43], [70, 45.5]];


// =============================================================================
// Helper modules
// =============================================================================

// Rounded rectangular prism using hull of corner cylinders.
// Rounding is applied to the four vertical edges only (common FDM-printable style).
module rbox(l, w, h, r) {
    hull() {
        for (xi = [r, l - r])
            for (yi = [r, w - r])
                translate([xi, yi, 0])
                    cylinder(r = r, h = h, $fn = 32);
    }
}

// Standoff boss: solid cylinder with a central hole for an M3 heat-set insert.
module boss(h, od, hole_d) {
    difference() {
        cylinder(d = od, h = h, $fn = 24);
        // Hole goes full depth + small overrun to avoid z-fighting
        translate([0, 0, -0.1])
            cylinder(d = hole_d, h = h + 0.2, $fn = 16);
    }
}

// Map PCB-relative coordinates to enclosure-relative coordinates.
// Use as a parent: pcb_at(px, py, pz) { children(); }
module pcb_at(px = 0, py = 0, pz = 0) {
    translate([PCB_OX + px, PCB_OY + py, pz])
        children();
}


// =============================================================================
// BASE — bottom tray with standoffs and cutouts
// =============================================================================
module base() {
    difference() {
        // ── Outer shell ───────────────────────────────────────────────────────
        color("SteelBlue", 0.9)
        rbox(OUT_L, OUT_W, OUT_H, CORNER_R);

        // ── Hollow interior cavity (open top) ─────────────────────────────────
        translate([WALL, WALL, FLOOR_T])
            cube([INNER_L, INNER_W, OUT_H]);   // Slightly over-tall — open top

        // ── Connector cutouts ─────────────────────────────────────────────────

        // J1 USB-C — LEFT wall (X = 0 face)
        // Slot origin: centred on USB-C body Y and Z; runs through the left wall.
        translate([-0.1,
                   PCB_OY + USBC_Y - USBC_CUT_W / 2,
                   USBC_CUT_Z])
            cube([WALL + 0.2, USBC_CUT_W, USBC_CUT_H]);

        // J2 JTAG — REAR wall (Y = OUT_W face, PCB top edge)
        translate([PCB_OX + JTAG_X - JTAG_CUT_W / 2,
                   OUT_W - WALL - 0.1,
                   JTAG_CUT_Z])
            cube([JTAG_CUT_W, WALL + 0.2, JTAG_CUT_H]);

        // J3 Expansion header — RIGHT wall (X = OUT_L face)
        translate([OUT_L - WALL - 0.1,
                   PCB_OY + (PCB_W - EXP_CUT_W) / 2,
                   EXP_CUT_Z])
            cube([WALL + 0.2, EXP_CUT_W, EXP_CUT_H]);

        // ── Ventilation slots — left wall and right wall ───────────────────────
        // Slots are evenly pitched along the Y axis of each side wall.
        for (i = [0 : VENT_COUNT - 1]) {
            // Left wall (X = 0)
            translate([-0.1,
                       WALL + VENT_MARGIN + i * VENT_PITCH,
                       VENT_Z])
                cube([WALL + 0.2, VENT_W, VENT_H]);

            // Right wall (X = OUT_L)
            translate([OUT_L - WALL - 0.1,
                       WALL + VENT_MARGIN + i * VENT_PITCH,
                       VENT_Z])
                cube([WALL + 0.2, VENT_W, VENT_H]);
        }

        // ── Lid screw holes (M3 clearance, countersunk from top) ──────────────
        for (mh = MH)
            pcb_at(mh[0], mh[1], OUT_H - WALL - 4)
                cylinder(d = M3_CLEAR, h = WALL + 5, $fn = 16);
    }

    // ── PCB standoff bosses (added, not subtracted) ───────────────────────────
    for (mh = MH)
        pcb_at(mh[0], mh[1], FLOOR_T)
            boss(STANDOFF_H, BOSS_OD, M3_INSERT);
}


// =============================================================================
// LID — flat plate with LED holes and M3 clearance holes
// =============================================================================
module lid() {
    difference() {
        // ── Outer plate ───────────────────────────────────────────────────────
        color("SlateGray", 0.85)
        rbox(OUT_L, OUT_W, LID_T, CORNER_R);

        // ── LED light-pipe holes ──────────────────────────────────────────────
        // Positioned to align with D2–D5 on the carrier board.
        for (lp = LED_POS)
            pcb_at(lp[0], lp[1], -0.1)
                cylinder(d = LED_D, h = LID_T + 0.2, $fn = 20);

        // ── M3 clearance holes aligned to standoff bosses ─────────────────────
        for (mh = MH)
            pcb_at(mh[0], mh[1], -0.1)
                cylinder(d = M3_CLEAR, h = LID_T + 0.2, $fn = 16);

        // ── Engraved label (0.4 mm deep recess on top surface) ───────────────
        translate([OUT_L / 2, OUT_W / 2, LID_T - 0.4])
            linear_extrude(0.5)
                text("TensorRail-Mini",
                     size    = 4.5,
                     halign  = "center",
                     valign  = "center",
                     $fn     = 32);
    }
}


// =============================================================================
// ASSEMBLY — base and lid placed together (or exploded for clarity)
// =============================================================================
module assembly(explode = 0) {
    base();
    translate([0, 0, OUT_H + explode])
        lid();
}


// =============================================================================
// Dispatch based on PART variable
// =============================================================================
if      (PART == "base")     { base(); }
else if (PART == "lid")      { lid(); }
else if (PART == "exploded") { assembly(explode = 20); }
else                         { assembly(explode = 0); }
