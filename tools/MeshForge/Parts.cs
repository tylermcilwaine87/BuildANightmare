// The sculpts. One function per part; coordinates are the part's own frame (studs, +Y up,
// -Z forward), matching the old block layout so joints, abilities and animations still
// line up: same joint pivots, same reach, same foot heights. Arms are authored as RIGHT
// arms (the forge writes a mirrored copy for the left); a leg or wing pair is authored as
// the right one in its own joint frame (AddPair mirrors it for the left).
using System;
using System.Collections.Generic;

public static class Parts
{
	static V3 V(double x, double y, double z) { return new V3(x, y, z); }
	static int[] RGB(int r, int g, int b) { return new[] { r, g, b }; }
	static Rot R(double x, double y, double z) { return Rot.Deg(x, y, z); }
	static readonly Rot I = Rot.Deg(0, 0, 0);

	static Sdf Mx(Sdf s) { return new MirrorX(s); }
	static Union U(double k, params Sdf[] s) { return new Union(k, s); }
	static Sdf Cut(Sdf a, Sdf b, double k) { return new Subtract(a, b, k); }
	static Sdf Both(Sdf a, Sdf b, double k) { return new Intersect(a, b, k); }
	static Sdf Rgh(Sdf s, double amp, double freq, int seed) { return new Rough(s, amp, freq, seed); }
	static Sdf Ball(V3 c, double r) { return new Sphere(c, r); }
	static Sdf Cone(V3 a, V3 b, double ra, double rb) { return new RoundCone(a, b, ra, rb); }
	static Sdf Ell(V3 c, V3 r) { return new Ellipsoid(c, r); }
	static Sdf Ell(V3 c, V3 r, Rot rot) { return new Ellipsoid(c, r, rot); }
	static Sdf Box(V3 c, V3 half, double round) { return new RoundBox(c, half, round, I); }
	static Sdf Box(V3 c, V3 half, double round, Rot rot) { return new RoundBox(c, half, round, rot); }
	static Sdf Ring(V3 c, double major, double minor, Rot rot) { return new Torus(c, major, minor, rot); }
	static Sdf Tube(double rBase, double rTip, params V3[] pts) { return Shapes.Path(pts, rBase, rTip); }
	static Sdf Ribbed(double rBase, double rTip, double ribs, double depth, params V3[] pts) { return Shapes.Path(pts, rBase, rTip, 8, ribs, depth); }
	static Sdf Horn(V3 a, V3 c, V3 b, double r0, double r1) { return Shapes.Horn(a, c, b, r0, r1); }
	static Sdf Grow(Sdf s, double by) { return new Offset(s, by); }
	static Sdf Shell(Sdf s, double thickness) { return Cut(s, Grow(s, -thickness), 0); }
	static Sdf Gem(V3 b, V3 axis, double r, double len, double twist) { return new Crystal(b, axis, r, len, r * 1.6, twist); }

	// A neck of vertebrae from the joint (the origin) up into the base of a skull, a spike on
	// the back of each, so a head that sits high still joins the body.
	static Sdf Neck(double top, double width, int seed)
	{
		var u = new Union(0.1, Tube(width * 0.62, width * 0.55, V(0, -0.15, 0.32), V(0, top * 0.5, 0.36), V(0, top, 0.42)));
		for (int i = 0; i < 3; i++)
		{
			double y = -0.05 + i * (top / 3.0), z = 0.32 + i * 0.04;
			u.Add(Ell(V(0, y, z), V(width, width * 0.42, width * 0.9)));
			u.Add(Cone(V(0, y + 0.05, z + width * 0.6), V(0, y + 0.2, z + width * 1.35), 0.07, 0.01));
		}
		return Rgh(u, 0.015, 5, seed);
	}

	// a ring of small round heads (rivets, studs) along a list of points
	static Sdf Studs(double r, params V3[] at)
	{
		var u = new Union(0);
		foreach (var p in at) u.Add(Ball(p, r));
		return u;
	}

	public static IEnumerable<PartSpec> All()
	{
		// cores
		yield return WoodenBody();
		yield return PeeperOrb();
		yield return ReinforcedCore();
		yield return ReactorHeart();
		yield return CrystalShell();
		yield return ObsidianHeart();
		// heads
		yield return CrackedSkull();
		yield return ElectricJaw();
		yield return FrostHorns();
		yield return ScrapVisor();
		yield return DragonSkull();
		// arms
		yield return RustyClaw();
		yield return ShadowTentacle();
		yield return DemonicClaws();
		yield return MagneticClaw();
		yield return TitanHammerArm();
		yield return InfernoGauntlet();
		// legs
		yield return JellyLegs();
		yield return DriftingWisp();
		yield return PhantomLegs();
		yield return ScrapLegs();
		yield return MangyHoundLegs();
		yield return VenomousSpiderLegs();
		// back
		yield return TinyBatWings();
		yield return VoidWings();
		yield return PhoenixWings();
		// tails
		yield return BentMetalTail();
		yield return ScorpionTail();
	}

	//======================================================================================
	// CORES (centred on the origin)
	//======================================================================================

	// WOODEN BODY: a haunted shipping crate - planks, a smashed corner bristling with
	// splinters, iron bands and corner brackets, and a jagged grinning face cut into the front
	// with something burning inside that shows through every crack.
	static PartSpec WoodenBody()
	{
		var p = new PartSpec("WoodenBody");
		Sdf body = Box(V(0, 0, 0), V(1.5, 1.42, 1.0), 0.1);
		Sdf crate = body;
		// plank seams: grooves around the outside only
		foreach (double y in new[] { -0.72, -0.24, 0.24, 0.72 })
			crate = Cut(crate, Cut(Box(V(0, y, 0), V(1.7, 0.03, 1.2), 0), Box(V(0, 0, 0), V(1.42, 1.6, 0.92), 0), 0), 0.015);
		// the smashed corner
		crate = Cut(crate, Rgh(Ball(V(-1.5, 1.45, -1.0), 0.6), 0.14, 3.2, 21), 0.03);
		// the face: slanted eye holes and a jagged grin with teeth left standing
		crate = Cut(crate, Mx(Ell(V(0.55, 0.48, -1.0), V(0.3, 0.16, 0.3), R(0, 0, 20))), 0.02);
		var mouth = new Union(0,
			Ell(V(0, -0.42, -1.0), V(0.95, 0.3, 0.3)),
			Ell(V(0, -0.25, -1.0), V(0.7, 0.2, 0.3)));
		var grinTeeth = new Union(0);
		for (int i = 0; i < 6; i++)
		{
			double x = -0.78 + i * 0.31;
			grinTeeth.Add(Cone(V(x, -0.12, -1.0), V(x + 0.03, -0.42, -1.0), 0.1, 0.012));
			if (i < 5) grinTeeth.Add(Cone(V(x + 0.155, -0.74, -1.0), V(x + 0.14, -0.46, -1.0), 0.09, 0.012));
		}
		crate = Cut(crate, Cut(mouth, grinTeeth, 0.01), 0.02);
		crate = new Cracked(Rgh(crate, 0.012, 5, 3), 1.1, 0.035, 0.1, 5);
		p.Add("Crate", crate, RGB(124, 92, 60), "Wood", null, 0.035, 3800);

		// the fire inside: just under the wood, showing through the face and the cracks
		p.Add("Glow", Grow(body, -0.075), RGB(255, 140, 40), "Neon", null, 0.06, 300);

		// iron: two bands, four corner brackets, rivets
		var iron = new Union(0.02);
		foreach (double y in new[] { -1.2, 1.2 })
			iron.Add(Cut(Box(V(0, y, 0), V(1.6, 0.17, 1.1), 0.04), Box(V(0, y, 0), V(1.48, 0.4, 0.98), 0), 0));
		foreach (double x in new[] { -1.5, 1.5 })
			foreach (double z in new[] { -1.0, 1.0 })
				iron.Add(Box(V(x, -0.05, z), V(0.13, 1.25, 0.13), 0.03));
		var rivets = new List<V3>();
		foreach (double x in new[] { -1.2, -0.6, 0, 0.6, 1.2 })
			foreach (double y in new[] { -1.2, 1.2 })
				foreach (double z in new[] { -1.11, 1.11 })
					rivets.Add(V(x, y, z));
		iron.Add(Studs(0.065, rivets.ToArray()));
		// (the smashed corner took the band with it)
		p.Add("Iron", Cut(Rgh(iron, 0.012, 7, 4), Ball(V(-1.5, 1.45, -1.0), 0.52), 0.02), RGB(58, 52, 50), "Metal", null, 0.03, 2400);

		// splinters bursting out of the broken corner
		var spl = new Union(0.02,
			Cone(V(-1.05, 1.0, -0.6), V(-1.45, 1.62, -0.95), 0.07, 0.006),
			Cone(V(-1.0, 1.1, -0.75), V(-1.62, 1.25, -1.05), 0.06, 0.005),
			Cone(V(-1.15, 0.95, -0.55), V(-1.3, 1.5, -1.2), 0.05, 0.005),
			Cone(V(-0.9, 1.25, -0.7), V(-1.1, 1.75, -0.9), 0.05, 0.005),
			Cone(V(-1.1, 1.2, -0.4), V(-1.58, 1.55, -0.55), 0.05, 0.005));
		p.Add("Splinters", spl, RGB(176, 136, 90), "Wood", null, 0.02, 500);
		return p;
	}

	// PEEPER ORB: a huge bloodshot eye bulging out of a pod of wrinkled flesh - the lids part
	// in an almond slit, a slit pupil in a blue iris, veins crawling in from the edges.
	static PartSpec PeeperOrb()
	{
		var p = new PartSpec("PeeperOrb");
		p.Add("Eyeball", Ball(V(0, 0, 0), 1.55), RGB(236, 230, 214), "SmoothPlastic", null, 0.06, 900);
		var almond = Both(Ell(V(0, -0.5, -1.6), V(1.35, 1.05, 1.1)), Ell(V(0, 0.6, -1.6), V(1.35, 1.05, 1.1)), 0.05);
		Sdf pod = Cut(Shell(Ball(V(0, 0, 0), 1.7), 0.18), almond, 0.18);
		// heavy lid folds along the opening, a fleshy stalk behind
		pod = U(0.12, pod, Cut(Ring(V(0, 0.05, -1.05), 1.02, 0.12, R(90, 0, 0)), almond, 0.1), Cone(V(0, 0, 0.9), V(0, -0.2, 1.75), 0.75, 0.45));
		pod = new Cracked(Rgh(pod, 0.03, 3.5, 31), 2.0, 0.025, 0.05, 32, 0.04);
		p.Add("Lids", pod, RGB(112, 52, 62), "SmoothPlastic", null, 0.04, 3200);
		p.Add("Iris", Both(Ball(V(0, 0, 0), 1.572), Ball(V(0, 0.05, -1.55), 0.74), 0), RGB(48, 128, 225), "SmoothPlastic", null, 0.025, 600);
		p.Add("Pupil", Both(Ball(V(0, 0, 0), 1.588), Ell(V(0, 0.05, -1.55), V(0.14, 0.52, 0.5)), 0), RGB(10, 8, 12), "SmoothPlastic", null, 0.02, 300);
		var glint = V(0.24, 0.34, -1.5).Unit() * 1.6;
		p.Add("Glint", Ball(glint, 0.1), RGB(255, 255, 255), "Neon", null, 0.02, 80);
		// veins: from the iris's rim outward over the white, wandering
		var veins = new Union(0);
		var rnd = new Random(7);
		for (int i = 0; i < 11; i++)
		{
			double phi = i * Math.PI * 2 / 11 + rnd.NextDouble() * 0.3;
			var pts = new List<V3>();
			for (int s = 0; s <= 4; s++)
			{
				double th = (31 + s * 11) * Math.PI / 180;
				double ph = phi + (rnd.NextDouble() - 0.5) * 0.25;
				pts.Add(V(Math.Sin(th) * Math.Cos(ph), Math.Sin(th) * Math.Sin(ph), -Math.Cos(th)) * 1.548);
			}
			veins.Add(Shapes.Path(pts.ToArray(), 0.026, 0.05, 4));
		}
		p.Add("Veins", veins, RGB(175, 30, 42), "SmoothPlastic", null, 0.018, 1400);
		return p;
	}

	// REINFORCED CORE: a battered armoured torso - riveted chest plate, overlapping belly
	// plates, a heavy collar, dents and scratches, a cyan reactor glow through the grille.
	static PartSpec ReinforcedCore()
	{
		var p = new PartSpec("ReinforcedCore");
		Sdf body = U(0.1,
			Box(V(0, -0.05, 0), V(1.62, 1.5, 1.12), 0.28),
			Box(V(0, 0.08, -1.1), V(1.22, 0.95, 0.14), 0.08, R(-4, 0, 0)),          // chest plate
			Box(V(0, -0.98, -1.06), V(1.12, 0.2, 0.12), 0.06, R(-10, 0, 0)),        // belly plates
			Box(V(0, -1.32, -0.98), V(1.02, 0.18, 0.12), 0.06, R(-14, 0, 0)));
		// the grille: three slits through the chest plate
		foreach (double y in new[] { 0.42, 0.2, -0.02 })
			body = Cut(body, Box(V(0, y, -1.3), V(0.75, 0.045, 0.32), 0.02), 0.01);
		// dents
		body = Cut(body, Ball(V(0.95, -0.55, -1.62), 0.42), 0.12);
		body = Cut(body, Ball(V(-1.95, 0.4, -0.3), 0.42), 0.12);
		body = Rgh(body, 0.005, 4, 41);
		p.Add("Body", body, RGB(99, 102, 110), "DiamondPlate", null, 0.04, 3400);
		p.Add("Glow", Box(V(0, 0.2, -0.98), V(0.82, 0.32, 0.06), 0.03), RGB(80, 220, 255), "Neon", null, 0.04, 200);
		var collar = U(0.05,
			Box(V(0, 1.05, 0), V(1.8, 0.3, 1.3), 0.14),
			Box(V(0, 1.38, 0.1), V(1.35, 0.1, 1.0), 0.05));
		p.Add("Collar", Rgh(collar, 0.01, 6, 43), RGB(70, 72, 80), "Metal", null, 0.04, 1500);
		var rivets = new List<V3>();
		for (int i = 0; i < 5; i++)
		{
			double x = -1.0 + i * 0.5;
			rivets.Add(V(x, 0.92, -1.27)); rivets.Add(V(x, -0.68, -1.24));
		}
		foreach (double y in new[] { -0.4, 0.25 }) { rivets.Add(V(1.12, y, -1.25)); rivets.Add(V(-1.12, y, -1.25)); }
		var bolts = U(0, Studs(0.065, rivets.ToArray()),
			Studs(0.17, V(1.4, -1.2, -1.12), V(-1.4, -1.2, -1.12), V(1.4, 0.55, -1.15), V(-1.4, 0.55, -1.15)));
		p.Add("Rivets", bolts, RGB(150, 150, 160), "Metal", null, 0.025, 900);
		return p;
	}

	// REACTOR HEART: a riveted steel sphere caged in straps, a blazing core behind the front
	// window, a heavy gold ring around its middle and two exhaust stacks venting light.
	static PartSpec ReactorHeart()
	{
		var p = new PartSpec("ReactorHeart");
		Sdf shell = Ball(V(0, 0, 0), 1.7);
		shell = Cut(shell, Ball(V(0, 0, -1.62), 0.98), 0.08);                               // the window
		foreach (double y in new[] { 0.95, -0.95 })
			shell = Cut(shell, Ring(V(0, y, 0), Math.Sqrt(1.7 * 1.7 - y * y), 0.035, I), 0.01);  // panel seams
		shell = Rgh(shell, 0.005, 4, 51);
		p.Add("Shell", shell, RGB(45, 45, 55), "Metal", null, 0.04, 2400);
		// the core and the glow in the stacks
		p.Add("Core", U(0, Ball(V(0, 0, -0.4), 1.18), Ball(V(1.2, 1.66, 0), 0.19), Ball(V(-1.2, 1.66, 0), 0.19)), RGB(255, 170, 40), "Neon", null, 0.04, 500);
		var cage = new Union(0.03);
		foreach (double yaw in new[] { -28.0, 0.0, 28.0 })
			cage.Add(Ring(V(0, 0, 0), 1.7, 0.065, R(0, yaw, 90)));
		// exhaust stacks: ribbed pipes, hollow at the top
		foreach (double x in new[] { 1.2, -1.2 })
		{
			Sdf stack = U(0.05, Ribbed(0.3, 0.27, 3, 0.1, V(x * 0.92, 0.85, 0), V(x, 1.35, 0), V(x, 1.78, 0)), Ring(V(x, 1.78, 0), 0.27, 0.05, I));
			cage.Add(Cut(stack, Cone(V(x, 1.55, 0), V(x, 2.2, 0), 0.19, 0.19), 0.02));
		}
		p.Add("Cage", Rgh(cage, 0.006, 8, 53), RGB(72, 72, 82), "Metal", null, 0.03, 3000);
		var gold = new Union(0.03, Ring(V(0, 0, 0), 1.9, 0.14, I));
		for (int i = 0; i < 8; i++)
		{
			double a = i * Math.PI / 4 + Math.PI / 8;
			gold.Add(Ball(V(Math.Cos(a) * 1.9, 0, Math.Sin(a) * 1.9), 0.2));
		}
		p.Add("Ring", gold, RGB(255, 196, 70), "Metal", null, 0.03, 1600);
		return p;
	}

	// CRYSTAL SHELL: a cracked geode - rough dark rock, clusters of faceted crystal bursting
	// out of it, and a glowing cavity of small crystals in its front.
	static PartSpec CrystalShell()
	{
		var p = new PartSpec("CrystalShell");
		Sdf rock = Rgh(Rgh(Ball(V(0, 0, 0), 1.5), 0.13, 1.5, 61), 0.03, 6, 62);
		rock = Cut(rock, Ell(V(0, -0.2, -1.5), V(0.78, 0.68, 0.62)), 0.1);                    // the geode cavity
		rock = new Cracked(rock, 1.6, 0.03, 0.07, 63);
		p.Add("Rock", rock, RGB(72, 58, 98), "Slate", null, 0.04, 3200);
		p.Add("Core", Ball(V(0, -0.2, -0.98), 0.5), RGB(205, 165, 255), "Neon", null, 0.04, 300);
		var purple = new Union(0);
		var blue = new Union(0);
		// the cavity's lining of small crystals, pointing at you
		var rnd = new Random(64);
		for (int i = 0; i < 9; i++)
		{
			double a = i * Math.PI * 2 / 9;
			V3 b = V(Math.Cos(a) * 0.42, -0.2 + Math.Sin(a) * 0.36, -1.0);
			V3 ax = V(Math.Cos(a) * 0.5, Math.Sin(a) * 0.45, -1);
			(i % 2 == 0 ? purple : blue).Add(Gem(b, ax, 0.07 + rnd.NextDouble() * 0.03, 0.42 + rnd.NextDouble() * 0.15, i * 17));
		}
		// three big clusters (front right, front left, top back) and a small one low behind
		purple.Add(Gem(V(0.5, 0.5, -0.7), V(0.35, 0.75, -0.55), 0.3, 1.45, 10));
		purple.Add(Gem(V(0.62, 0.35, -0.8), V(0.8, 0.35, -0.5), 0.17, 0.95, 30));
		purple.Add(Gem(V(0.35, 0.65, -0.75), V(-0.05, 0.9, -0.5), 0.15, 0.85, 50));
		blue.Add(Gem(V(-0.55, 0.3, -0.75), V(-0.5, 0.55, -0.65), 0.26, 1.2, 20));
		blue.Add(Gem(V(-0.7, 0.15, -0.7), V(-0.9, 0.2, -0.45), 0.15, 0.8, 0));
		blue.Add(Gem(V(-0.45, 0.45, -0.85), V(-0.2, 0.8, -0.7), 0.13, 0.75, 40));
		purple.Add(Gem(V(0, 0.9, 0.35), V(0.12, 0.7, 0.7), 0.3, 1.25, 15));
		purple.Add(Gem(V(0.25, 0.8, 0.45), V(0.6, 0.55, 0.6), 0.16, 0.85, 35));
		blue.Add(Gem(V(-0.22, 0.85, 0.42), V(-0.45, 0.75, 0.55), 0.17, 0.9, 5));
		blue.Add(Gem(V(0.9, -0.6, 0.5), V(0.75, -0.3, 0.6), 0.2, 0.8, 25));
		blue.Add(Gem(V(1.0, -0.45, 0.35), V(0.9, 0.1, 0.2), 0.12, 0.6, 45));
		var gp = p.Add("CrystalsA", purple, RGB(170, 120, 255), "Glass", null, 0.025, 2200);
		gp.Transparency = 0.2;
		var gb = p.Add("CrystalsB", blue, RGB(120, 200, 255), "Glass", null, 0.025, 2000);
		gb.Transparency = 0.2;
		return p;
	}

	// OBSIDIAN HEART: a lump of volcanic glass split by veins of lava, a molten heart showing
	// through a wound in its front, black glass shards standing out of it.
	static PartSpec ObsidianHeart()
	{
		var p = new PartSpec("ObsidianHeart");
		Sdf rock = Rgh(Rgh(Ball(V(0, 0, 0), 1.58), 0.09, 1.7, 71), 0.025, 5.5, 72);
		var magma = Grow(rock, -0.09);
		Sdf shell = Cut(rock, Ell(V(0, -0.05, -1.62), V(0.62, 0.74, 0.42), R(0, 0, 8)), 0.08);
		shell = new Cracked(shell, 1.5, 0.05, 0.16, 73);
		p.Add("Shell", shell, RGB(52, 40, 62), "Glass", null, 0.04, 3600);
		p.Add("Magma", magma, RGB(255, 96, 22), "Neon", null, 0.06, 800);
		var shards = new Union(0,
			Gem(V(0.75, 0.55, -0.45), V(0.45, 0.8, -0.4), 0.36, 1.35, 12),
			Gem(V(0.95, 0.35, -0.2), V(0.9, 0.45, -0.1), 0.18, 0.85, 40),
			Gem(V(-0.8, 0.45, -0.4), V(-0.5, 0.75, -0.4), 0.32, 1.2, 25),
			Gem(V(-0.55, 0.65, -0.55), V(-0.1, 0.9, -0.5), 0.16, 0.8, 5),
			Gem(V(0, 0.95, 0.45), V(0.05, 0.75, 0.65), 0.38, 1.15, 33),
			Gem(V(0.3, 0.9, 0.55), V(0.5, 0.6, 0.7), 0.17, 0.8, 9),
			Gem(V(-0.95, -0.7, 0.35), V(-0.7, -0.4, 0.55), 0.2, 0.7, 50),
			Gem(V(1.0, -0.75, 0.2), V(0.7, -0.55, 0.3), 0.16, 0.6, 18));
		p.Add("Shards", Cut(shards, Ball(V(0, 0, 0), 1.2), 0), RGB(80, 62, 96), "Glass", null, 0.025, 2200);
		return p;
	}

	//======================================================================================
	// HEADS (the neck joint at the origin, the head above it)
	//======================================================================================

	// CRACKED SKULL: an old cracked human skull - deep sockets with embers in them, a broken
	// nose cavity, blunt worn teeth, a hinged jaw and a knuckle of spine underneath.
	static PartSpec CrackedSkull()
	{
		var p = new PartSpec("CrackedSkull");
		p.Group("Jaw", V(0, 0.6, 0.3));
		var bone = RGB(230, 224, 204);
		Sdf skull = U(0.25,
			Ell(V(0, 1.42, 0.08), V(0.98, 0.95, 1.08)),                            // cranium
			Ell(V(0, 0.82, -0.52), V(0.62, 0.4, 0.5)),                             // upper jaw
			Mx(Ell(V(0.6, 1.0, -0.58), V(0.25, 0.2, 0.32))),                        // cheekbones
			Mx(Cone(V(0.14, 1.52, -0.98), V(0.68, 1.58, -0.78), 0.12, 0.1)),        // brow
			Ell(V(0, 0.82, 0.55), V(0.55, 0.42, 0.42)),                             // the back of the skull
			Cone(V(0, 0.05, 0.25), V(0, 0.65, 0.32), 0.24, 0.26));                  // a stub of spine
		skull = Cut(skull, Mx(Ell(V(0.42, 1.25, -0.92), V(0.28, 0.25, 0.32))), 0.06);            // eye sockets
		skull = Cut(skull, Mx(Ell(V(0.08, 0.93, -1.0), V(0.09, 0.17, 0.22), R(0, 0, -15))), 0.03); // nose cavity
		skull = Cut(skull, Mx(Ell(V(1.02, 1.25, 0.05), V(0.18, 0.35, 0.5))), 0.12);              // temples
		skull = Cut(skull, Box(V(0, 0.1, -0.55), V(1.2, 0.34, 0.75), 0.05), 0.08);              // the mouth
		// the big crack across the crown and the brow, then smaller ones everywhere
		skull = Cut(skull, Tube(0.045, 0.02, V(0.1, 2.35, 0.2), V(0.3, 2.2, -0.35), V(0.18, 1.95, -0.75), V(0.32, 1.72, -0.98), V(0.25, 1.55, -1.02)), 0.02);
		skull = Cut(skull, Tube(0.03, 0.015, V(0.3, 2.2, -0.35), V(0.62, 2.1, -0.4), V(0.8, 1.9, -0.55)), 0.015);
		skull = new Cracked(Rgh(skull, 0.015, 4, 81), 1.1, 0.022, 0.05, 82);
		p.Add("Skull", skull, bone, "SmoothPlastic", null, 0.035, 3600);
		// dark hollows behind the sockets and the nose, embers in the eyes, the mouth's inside
		// (flat discs at the back of the sockets and the nose cavity, so they read as deep holes)
		p.Add("Hollows", U(0, Mx(Ell(V(0.42, 1.25, -0.66), V(0.25, 0.22, 0.1))), Ell(V(0, 0.93, -0.86), V(0.15, 0.17, 0.06))), RGB(22, 18, 22), "SmoothPlastic", null, 0.03, 300);
		p.Add("Embers", Mx(Ball(V(0.42, 1.22, -0.83), 0.1)), RGB(255, 110, 40), "Neon", null, 0.02, 160);
		p.Add("Mouth", Ell(V(0, 0.52, -0.38), V(0.55, 0.12, 0.45)), RGB(80, 22, 28), "SmoothPlastic", null, 0.04, 200);
		var teeth = new Union(0, Mx(Shapes.Teeth(V(0.07, 0.48, -0.99), V(0.47, 0.48, -0.74), 4, V(0, -1, -0.05), 0.17, 0.07, 0.55)));
		p.Add("Teeth", Rgh(teeth, 0.008, 9, 83), RGB(240, 232, 210), "SmoothPlastic", null, 0.02, 700);
		// the jaw (rides the Jaw hinge)
		var jaw = U(0.12,
			Ell(V(0, 0.2, -0.8), V(0.3, 0.19, 0.18)),                               // chin
			Mx(Cone(V(0.14, 0.2, -0.82), V(0.55, 0.3, -0.15), 0.15, 0.14)),          // body
			Mx(Cone(V(0.55, 0.3, -0.15), V(0.56, 0.68, 0.25), 0.13, 0.1)),           // ramus
			Mx(Ball(V(0.56, 0.72, 0.28), 0.12)));                                   // hinge knob
		p.Add("Jaw", new Cracked(Rgh(jaw, 0.014, 4, 84), 1.3, 0.02, 0.04, 85), RGB(215, 207, 184), "SmoothPlastic", "Jaw", 0.03, 1500);
		var jawTeeth = Mx(Shapes.Teeth(V(0.07, 0.33, -0.86), V(0.42, 0.35, -0.58), 4, V(0, 1, 0.05), 0.13, 0.065, 0.55));
		p.Add("JawTeeth", jawTeeth, RGB(240, 232, 210), "SmoothPlastic", "Jaw", 0.02, 500);
		return p;
	}

	// ELECTRIC JAW: a riveted robot helm - angry visor slits, tesla coils for ears, an
	// antenna coil with a crackling bulb, steel fangs, and a heavy hinged jaw with a charged
	// glow inside the mouth.
	static PartSpec ElectricJaw()
	{
		var p = new PartSpec("ElectricJaw");
		p.Group("Jaw", V(0, 0.5, 0.55));
		Sdf helm = U(0.12,
			Box(V(0, 1.2, 0.05), V(1.0, 0.7, 0.95), 0.3),
			Box(V(0, 1.62, -0.55), V(1.02, 0.12, 0.42), 0.06, R(-10, 0, 0)),      // brow plate
			Box(V(0, 1.9, 0.12), V(0.13, 0.1, 0.8), 0.05),                         // crest
			Box(V(0, 0.9, -0.8), V(0.85, 0.3, 0.2), 0.12, R(15, 0, 0)));           // snout plate
		helm = Cut(helm, Box(V(0, 0.42, -0.55), V(0.84, 0.18, 0.6), 0.06), 0.04);                 // the mouth
		helm = Cut(helm, Mx(Box(V(0.5, 1.38, -0.98), V(0.28, 0.07, 0.2), 0.03, R(0, 0, 12))), 0.01); // visor slits
		for (int i = 0; i < 3; i++)
			helm = Cut(helm, Mx(Box(V(1.02, 0.95 + i * 0.17, -0.25), V(0.1, 0.045, 0.3), 0.02)), 0.01); // cheek vents
		helm = Rgh(helm, 0.005, 4, 91);
		p.Add("Helm", helm, RGB(80, 90, 110), "Metal", null, 0.04, 3000);
		p.Add("Eyes", Mx(Box(V(0.5, 1.38, -0.81), V(0.3, 0.1, 0.05), 0.03, R(0, 0, 12))), RGB(90, 230, 255), "Neon", null, 0.025, 200);
		var studs = new List<V3>();
		for (int i = 0; i < 5; i++) studs.Add(V(-0.8 + i * 0.4, 1.74, -0.92));
		foreach (double y in new[] { 0.85, 1.55 }) { studs.Add(V(1.08, y, 0.45)); studs.Add(V(-1.08, y, 0.45)); }
		var copper = U(0.03,
			Mx(Cone(V(0.92, 1.15, 0.15), V(1.3, 1.15, 0.15), 0.1, 0.08)),                                   // tesla coils
			Mx(Ring(V(1.02, 1.15, 0.15), 0.17, 0.045, R(0, 0, 90))),
			Mx(Ring(V(1.14, 1.15, 0.15), 0.15, 0.045, R(0, 0, 90))),
			Mx(Ring(V(1.26, 1.15, 0.15), 0.13, 0.045, R(0, 0, 90))),
			Mx(Ball(V(1.36, 1.15, 0.15), 0.1)),
			Ribbed(0.085, 0.06, 7, 0.35, V(0, 1.9, 0.25), V(0, 2.35, 0.27), V(0, 2.7, 0.18)),               // antenna coil
			Studs(0.06, studs.ToArray()));
		p.Add("Copper", copper, RGB(186, 112, 62), "Metal", null, 0.02, 2200);
		p.Add("Bulb", Ball(V(0, 2.9, 0.15), 0.22), RGB(255, 240, 90), "Neon", null, 0.02, 300);
		var fangs = Mx(new Union(0, Shapes.Teeth(V(0.15, 0.62, -0.95), V(0.75, 0.62, -0.62), 4, V(0, -1, 0), 0.24, 0.065, 0.1)));
		p.Add("Fangs", fangs, RGB(200, 205, 215), "Metal", null, 0.02, 700);
		var glow = p.Add("MouthGlow", Ell(V(0, 0.48, -0.35), V(0.72, 0.1, 0.55)), RGB(60, 150, 255), "Neon", null, 0.03, 200);
		glow.Transparency = 0.25;
		// the jaw
		Sdf jaw = U(0.1,
			Box(V(0, 0.2, -0.22), V(0.86, 0.22, 0.82), 0.14, R(-6, 0, 0)),
			Box(V(0, 0.08, -0.95), V(0.6, 0.18, 0.15), 0.08, R(-20, 0, 0)),         // chin guard
			Mx(Cone(V(0.78, 0.5, 0.55), V(0.98, 0.5, 0.55), 0.17, 0.17)),             // hinge drums
			Mx(Box(V(0.82, 0.32, 0.25), V(0.08, 0.22, 0.3), 0.05)));
		p.Add("Jaw", Rgh(jaw, 0.005, 4, 93), RGB(65, 72, 90), "Metal", "Jaw", 0.035, 1800);
		var jawFangs = Mx(Shapes.Teeth(V(0.25, 0.4, -0.9), V(0.65, 0.4, -0.6), 3, V(0, 1, 0), 0.22, 0.06, 0.1));
		p.Add("JawFangs", jawFangs, RGB(200, 205, 215), "Metal", "Jaw", 0.02, 500);
		return p;
	}

	// FROST HORNS: a frozen beast's head - a goat-like skull of fractured ice, huge ribbed
	// ram horns curling round beside it, a crown of ice crystals, icicles hanging off the jaw,
	// pale cyan eyes.
	static PartSpec FrostHorns()
	{
		var p = new PartSpec("FrostHorns");
		Sdf head = U(0.28,
			Ell(V(0, 1.25, 0.12), V(0.8, 0.78, 0.85)),
			Cone(V(0, 1.18, -0.35), V(0, 0.84, -0.98), 0.52, 0.33),               // muzzle
			Ell(V(0, 0.68, -0.42), V(0.45, 0.25, 0.5)),                            // jaw
			Mx(Cone(V(0.12, 1.55, -0.62), V(0.62, 1.62, -0.42), 0.13, 0.15)),       // brow
			Mx(Ell(V(0.55, 1.0, -0.3), V(0.25, 0.25, 0.4))));                      // cheeks
		head = Cut(head, Mx(Ell(V(0.44, 1.33, -0.7), V(0.22, 0.12, 0.16), R(0, 25, -22))), 0.05);
		head = Cut(head, Mx(Ball(V(0.13, 0.95, -1.27), 0.07)), 0.03);
		head = new Cracked(Rgh(head, 0.02, 4, 101), 1.6, 0.02, 0.045, 102);
		p.Add("Head", head, RGB(170, 212, 238), "Ice", null, 0.035, 3000);
		p.Add("Eyes", Mx(Ell(V(0.44, 1.33, -0.74), V(0.18, 0.07, 0.08), R(0, 25, -22))), RGB(120, 240, 255), "Neon", null, 0.02, 240);
		p.Add("Neck", Neck(0.62, 0.34, 104), RGB(150, 196, 226), "Ice", null, 0.03, 1000);
		// ram horns: up from the crown, back, down and round, ending forward beside the cheek
		var horn = Ribbed(0.25, 0.05, 15, 0.09,
			V(0.36, 1.82, 0.05), V(0.7, 2.3, 0.15), V(1.05, 2.42, 0.55), V(1.3, 2.12, 0.95),
			V(1.42, 1.65, 0.85), V(1.36, 1.32, 0.4), V(1.25, 1.42, 0.0), V(1.18, 1.72, -0.12));
		p.Add("Horns", Rgh(Mx(horn), 0.012, 8, 103), RGB(214, 238, 252), "Ice", null, 0.03, 3200);
		// the crown of crystals and the icicles under the jaw and the brow
		var ice = new Union(0,
			Gem(V(0, 1.8, -0.1), V(0, 1, 0.12), 0.15, 0.75, 0),
			Mx(Gem(V(0.2, 1.78, 0.08), V(0.35, 1, 0.3), 0.11, 0.55, 20)),
			Mx(Gem(V(0.12, 1.75, 0.3), V(0.15, 0.9, 0.6), 0.09, 0.45, 40)),
			Mx(Shapes.Teeth(V(0.1, 0.48, -0.72), V(0.36, 0.52, -0.2), 4, V(0, -1, 0.1), 0.24, 0.055, 0.05)),
			Mx(Shapes.Teeth(V(0.3, 1.47, -0.82), V(0.62, 1.52, -0.58), 3, V(0, -1, -0.1), 0.15, 0.04, 0.05)));
		var g = p.Add("Crystals", ice, RGB(200, 238, 255), "Glass", null, 0.02, 1600);
		g.Transparency = 0.15;
		return p;
	}

	// SCRAP VISOR: a battered welder's mask - dented and scratched, patched with rusty
	// plates, one burning slit of a visor, a corroded brim, a breathing grille, and a gas
	// canister on its cheek with a ribbed hose round the back.
	static PartSpec ScrapVisor()
	{
		var p = new PartSpec("ScrapVisor");
		Sdf mask = U(0.22,
			Box(V(0, 1.0, 0.05), V(1.0, 0.78, 0.9), 0.38),
			Ell(V(0, 1.05, -0.5), V(0.95, 0.74, 0.5)),
			Ell(V(0, 0.55, -0.68), V(0.55, 0.3, 0.36)));
		mask = Cut(mask, Ball(V(0.65, 1.5, -1.25), 0.32), 0.15);           // dents
		mask = Cut(mask, Ball(V(-0.75, 0.68, -1.12), 0.26), 0.15);
		mask = Cut(mask, Box(V(0, 1.15, -1.05), V(0.8, 0.13, 0.3), 0.04), 0.01);  // the slit
		for (int i = 0; i < 3; i++)
			mask = Cut(mask, Box(V(0, 0.44 + i * 0.12, -1.02), V(0.32, 0.03, 0.12), 0.02), 0.01); // grille
		mask = Rgh(mask, 0.008, 4, 111);
		p.Add("Mask", mask, RGB(85, 85, 95), "Metal", null, 0.04, 3000);
		p.Add("Glow", Box(V(0, 1.15, -0.8), V(0.82, 0.16, 0.06), 0.03), RGB(255, 120, 40), "Neon", null, 0.03, 160);
		var rust = U(0.03,
			Cut(Box(V(0, 1.15, -0.98), V(0.95, 0.26, 0.09), 0.04, R(0, 0, 0)), Box(V(0, 1.15, -1.0), V(0.8, 0.13, 0.4), 0.02), 0), // slit frame
			Box(V(-0.55, 0.62, -0.98), V(0.28, 0.2, 0.05), 0.02, R(-25, 12, 14)),                 // patches
			Box(V(0.78, 1.55, -0.55), V(0.22, 0.2, 0.05), 0.02, R(-40, 35, -10)),
			Box(V(0, 1.74, -0.45), V(0.98, 0.06, 0.55), 0.03, R(-10, 0, 0)),                   // the brim (a forehead plate)
			Box(V(0, 1.66, -1.0), V(0.9, 0.05, 0.1), 0.03, R(30, 0, 0)));
		p.Add("Rust", Rgh(rust, 0.03, 4, 113), RGB(122, 70, 40), "CorrodedMetal", null, 0.025, 2200);
		var rivets = new List<V3>();
		for (int i = 0; i < 4; i++) { rivets.Add(V(-0.85 + i * 0.567, 1.4, -1.07)); rivets.Add(V(-0.85 + i * 0.567, 0.9, -1.07)); }
		var can = U(0.03,
			Ribbed(0.19, 0.19, 3, 0.1, V(0.75, 0.5, 0), V(0.98, 0.5, 0), V(1.22, 0.5, 0)),
			Ball(V(1.24, 0.5, 0), 0.12),
			Ribbed(0.065, 0.06, 14, 0.25, V(1.12, 0.52, 0.12), V(1.1, 0.7, 0.6), V(0.75, 0.95, 0.98), V(0.2, 1.0, 1.02)),
			Studs(0.055, rivets.ToArray()));
		p.Add("Canister", can, RGB(60, 60, 68), "Metal", null, 0.02, 2200);
		return p;
	}

	// DRAGON SKULL (jaw on Sub_Head_Jaw): a heavy dark-red skull that narrows into a long
	// snout, brow ridges overhanging deep-set glowing eyes, cheekbones, nostrils, a jagged
	// row of teeth, bone horns swept back and spikes along the crown.
	static PartSpec DragonSkull()
	{
		var p = new PartSpec("DragonSkull");
		var jawPivot = V(0, 0.55, 0.45);
		p.Group("Jaw", jawPivot);

		var skin = RGB(60, 13, 17);
		var bone = RGB(214, 198, 172);
		var eye = RGB(255, 28, 22);

		// --- the skull (upper jaw) ---
		var skull = new Union(0.32,
			new Ellipsoid(V(0, 1.32, 0.3), V(0.86, 0.6, 0.8)),               // cranium
			new Ellipsoid(V(0, 1.08, 0.8), V(0.78, 0.55, 0.5)),              // back of the skull
			new Ellipsoid(V(0, 1.1, -1.0), V(0.6, 0.46, 0.82)),               // snout
			new RoundCone(V(0, 1.25, -0.45), V(0, 1.06, -1.72), 0.56, 0.36),  // snout taper
			new RoundCone(V(0, 1.56, -0.4), V(0, 1.36, -1.56), 0.28, 0.18),   // bridge of the nose
			new MirrorX(new Union(0.18,
				new RoundCone(V(0.16, 1.6, -0.64), V(0.7, 1.72, -0.42), 0.13, 0.15),   // brow ridge: low at the middle, an angry V
				new Ellipsoid(V(0.7, 1.05, -0.35), V(0.28, 0.26, 0.5)),                 // cheekbone
				new Ellipsoid(V(0.22, 1.3, -1.64), V(0.16, 0.11, 0.17))                  // nostril
			))
		);
		// eye sockets, nostril holes, and the mouth cut flat underneath (the jaw closes on it)
		Sdf carved = new Subtract(skull, new MirrorX(new Ellipsoid(V(0.52, 1.5, -0.74), V(0.27, 0.13, 0.16), R(0, 25, -22))), 0.06);
		carved = new Subtract(carved, new MirrorX(new Sphere(V(0.24, 1.32, -1.78), 0.065)), 0.03);
		carved = new Subtract(carved, new RoundBox(V(0, 0.3, -1.1), V(1.3, 0.47, 1.35), 0.05, R(0, 0, 0)), 0.08);
		p.Add("Skull", new Rough(carved, 0.03, 4.2, 7), skin, "SmoothPlastic", null, 0.035, 3200);

		// --- the jaw ---
		var jaw = new Union(0.25,
			new RoundCone(V(0, 0.76, 0.2), V(0, 0.66, -1.56), 0.36, 0.24),
			new Ellipsoid(V(0, 0.66, -0.65), V(0.55, 0.2, 0.92)),
			new MirrorX(new Ellipsoid(V(0.48, 0.78, 0.2), V(0.18, 0.2, 0.3)))   // the jaw's hinge
		);
		Sdf jawCut = new Subtract(jaw, new RoundBox(V(0, 1.2, -1.0), V(1.3, 0.42, 1.6), 0.05, R(0, 0, 0)), 0.06);
		p.Add("Jaw", new Rough(jawCut, 0.022, 4.5, 11), RGB(58, 12, 17), "SmoothPlastic", "Jaw", 0.035, 1300);

		// --- teeth: jagged, uneven ---
		var upperTeeth = new Union(0.0,
			new MirrorX(Shapes.Teeth(V(0.5, 0.82, -0.35), V(0.32, 0.8, -1.66), 7, V(0.05, -1, -0.15), 0.24, 0.06)),
			Shapes.Teeth(V(-0.17, 0.8, -1.8), V(0.17, 0.8, -1.8), 3, V(0, -1, -0.25), 0.2, 0.05)
		);
		p.Add("Teeth", upperTeeth, bone, "SmoothPlastic", null, 0.025, 900);
		var lowerTeeth = new MirrorX(Shapes.Teeth(V(0.44, 0.77, -0.3), V(0.26, 0.75, -1.48), 6, V(0.05, 1, -0.1), 0.18, 0.05));
		p.Add("JawTeeth", lowerTeeth, bone, "SmoothPlastic", "Jaw", 0.025, 700);

		// --- horns and spikes ---
		var horns = new Union(0.06,
			new MirrorX(new Union(0.05,
				Shapes.Horn(V(0.36, 1.8, 0.05), V(0.56, 2.5, 0.2), V(0.46, 3.05, 0.78), 0.21, 0.02),    // the great horns, tall and curving back
				Shapes.Horn(V(0.62, 1.62, 0.5), V(1.02, 1.88, 0.98), V(1.18, 1.98, 1.6), 0.15, 0.015),   // swept-back side horns
				Shapes.Horn(V(0.84, 1.12, 0.12), V(1.1, 1.18, 0.42), V(1.32, 1.3, 0.75), 0.09, 0.012)   // cheek spikes
			)),
			Shapes.Horn(V(0, 1.86, 0.55), V(0, 2.12, 0.78), V(0, 2.22, 1.05), 0.09, 0.012),                 // the crest
			Shapes.Horn(V(0, 1.7, 0.95), V(0, 1.95, 1.2), V(0, 2.05, 1.5), 0.08, 0.012)
		);
		p.Add("Horns", new Rough(horns, 0.01, 9, 3), bone, "SmoothPlastic", null, 0.03, 1600);

		// --- eyes: slanted, glowing, set deep under the brow ---
		p.Add("Eyes", new MirrorX(new Ellipsoid(V(0.5, 1.5, -0.78), V(0.23, 0.085, 0.1), R(0, 25, -22))), eye, "Neon", null, 0.02, 300);
		p.Add("Neck", Neck(0.72, 0.36, 12), RGB(48, 10, 14), "SmoothPlastic", null, 0.03, 1000);
		return p;
	}

	//======================================================================================
	// ARMS (RIGHT arms: the shoulder at the origin, hanging down; the Fore group bends at
	// the elbow - its meshes are authored in the part frame too)
	//======================================================================================

	// RUSTY CLAW: a corroded mechanical arm - a riveted pauldron, banded pipe limbs, a heavy
	// wrist and three hooked steel talons with a thumb hook.
	static PartSpec RustyClaw()
	{
		var p = new PartSpec("RustyClaw") { ArmMirror = true };
		p.Group("Fore", V(0.5, -1.0, 0));
		var rust = RGB(150, 85, 50);
		var upper = U(0.08,
			Ell(V(0.25, 0.1, 0), V(0.52, 0.38, 0.52)),                                         // pauldron
			Box(V(0.38, 0.32, 0), V(0.45, 0.07, 0.45), 0.05, R(0, 0, -15)),
			Tube(0.28, 0.24, V(0.2, -0.05, 0), V(0.38, -0.5, 0), V(0.5, -0.92, 0)),
			Ring(V(0.36, -0.42, 0), 0.27, 0.05, R(0, 0, 10)),
			Ring(V(0.45, -0.75, 0), 0.25, 0.05, R(0, 0, 10)),
			Studs(0.05, V(0.1, 0.38, -0.32), V(0.45, 0.32, -0.38), V(0.7, 0.18, -0.3)));
		p.Add("Upper", Rgh(upper, 0.016, 4, 121), rust, "CorrodedMetal", null, 0.03, 2400);
		p.Add("Elbow", Rgh(Ball(V(0.5, -1.0, 0), 0.31), 0.015, 5, 123), RGB(120, 70, 40), "CorrodedMetal", null, 0.03, 500);
		var fore = U(0.08,
			Tube(0.25, 0.3, V(0.5, -1.05, 0), V(0.55, -1.5, 0), V(0.6, -1.92, 0)),
			Ring(V(0.56, -1.55, 0), 0.28, 0.05, R(0, 0, 6)),
			Box(V(0.6, -2.12, 0), V(0.36, 0.25, 0.42), 0.13),                                   // the hand
			Studs(0.13, V(0.6, -2.33, -0.3), V(0.6, -2.35, 0), V(0.6, -2.33, 0.3)),             // knuckles
			Studs(0.05, V(0.97, -2.05, -0.2), V(0.97, -2.05, 0.2)));
		p.Add("Fore", Rgh(fore, 0.016, 4, 124), rust, "CorrodedMetal", "Fore", 0.03, 2400);
		var talons = new Union(0.02);
		foreach (double z in new[] { -0.3, 0.0, 0.3 })
			talons.Add(Horn(V(0.6, -2.3, z), V(0.63, -2.88, z + 0.06), V(0.55, -3.15, z - 0.3), 0.11, 0.012));
		talons.Add(Horn(V(0.32, -2.12, -0.22), V(0.18, -2.55, -0.3), V(0.3, -2.8, -0.5), 0.085, 0.01));
		p.Add("Talons", Rgh(talons, 0.006, 10, 126), RGB(190, 180, 170), "Metal", "Fore", 0.022, 1500);
		return p;
	}

	// SHADOW TENTACLE: a thick coil of living darkness, rows of suckers down its front, glowing
	// spots down its back and a bioluminescent lure at the tip.
	static PartSpec ShadowTentacle()
	{
		var p = new PartSpec("ShadowTentacle") { ArmMirror = true };
		var pivot = V(0.8, -1.55, -0.2);
		p.Group("Fore", pivot);
		var upperPts = new[] { V(0.1, 0.0, 0.0), V(0.4, -0.5, 0.0), V(0.7, -1.2, -0.1), V(0.82, -1.62, -0.22) };
		var forePts = new[] { V(0.8, -1.5, -0.2), V(0.9, -1.9, -0.3), V(1.0, -2.6, -0.5), V(1.0, -3.2, -0.8), V(1.0, -3.55, -1.0) };
		p.Add("Upper", Rgh(Tube(0.48, 0.37, upperPts), 0.02, 4, 131), RGB(45, 25, 70), "SmoothPlastic", null, 0.035, 1800);
		p.Add("Fore", Rgh(Tube(0.36, 0.08, forePts), 0.015, 4, 132), RGB(58, 32, 90), "SmoothPlastic", "Fore", 0.03, 2200);
		// suckers on the front, glowing spots on the back
		Func<V3[], double, double, Union[]> dress = (pts, r0, r1) =>
		{
			var suckers = new Union(0);
			var spots = new Union(0);
			var s = Shapes.Spline(pts, 4);
			for (int i = 1; i < s.Count - 1; i++)
			{
				double t = (double)i / (s.Count - 1), r = r0 + (r1 - r0) * Math.Pow(t, 0.9);
				V3 tan = (s[i + 1] - s[i - 1]).Unit();
				V3 front = V(-0.25, 0.1, -1);
				front = (front - tan * front.Dot(tan)).Unit();
				double sr = r * 0.32;
				V3 c = s[i] + front * (r * 0.88);
				suckers.Add(Cut(Ball(c, sr), Ball(c + front * sr * 0.7, sr * 0.62), 0.01));
				if (i % 2 == 0) spots.Add(Ball(s[i] - front * (r * 0.92), r * 0.12));
			}
			return new[] { suckers, spots };
		};
		var up = dress(upperPts, 0.48, 0.37);
		var fo = dress(forePts, 0.36, 0.08);
		p.Add("Suckers", up[0], RGB(112, 72, 142), "SmoothPlastic", null, 0.02, 1200);
		p.Add("ForeSuckers", fo[0], RGB(112, 72, 142), "SmoothPlastic", "Fore", 0.018, 1400);
		p.Add("Spots", up[1], RGB(180, 90, 255), "Neon", null, 0.02, 300);
		p.Add("Lure", U(0, fo[1], Ball(V(1.0, -3.62, -1.04), 0.15)), RGB(180, 90, 255), "Neon", "Fore", 0.018, 500);
		return p;
	}

	// DEMONIC CLAWS: a muscled demon arm, the skin split by veins of fire that glow brighter
	// the angrier it gets, black horn spikes at shoulder, elbow and forearm, and three long
	// curved blades of burning metal.
	static PartSpec DemonicClaws()
	{
		var p = new PartSpec("DemonicClaws") { ArmMirror = true };
		p.Group("Fore", V(0.58, -1.1, 0));
		var skin = RGB(130, 25, 35);
		var fire = RGB(255, 60, 40);
		Sdf upperMuscle = Rgh(U(0.2,
			Ell(V(0.35, -0.05, 0), V(0.5, 0.45, 0.5)),                  // shoulder
			Ell(V(0.5, -0.58, -0.08), V(0.4, 0.5, 0.38)),               // bicep
			Ell(V(0.54, -0.62, 0.12), V(0.38, 0.48, 0.36)),             // tricep
			Ball(V(0.58, -1.1, 0), 0.4)), 0.025, 4, 141);               // elbow
		p.Add("Upper", new Cracked(upperMuscle, 1.9, 0.03, 0.07, 142), skin, "Slate", null, 0.035, 2600);
		p.Add("UpperVeins", Grow(upperMuscle, -0.045), fire, "Neon", null, 0.05, 500);
		Sdf foreMuscle = Rgh(U(0.18,
			Tube(0.4, 0.34, V(0.6, -1.2, 0), V(0.66, -1.75, 0), V(0.68, -2.18, 0)),
			Box(V(0.7, -2.5, 0), V(0.5, 0.3, 0.5), 0.18),               // the hand
			Studs(0.17, V(0.7, -2.75, -0.4), V(0.72, -2.78, 0), V(0.7, -2.75, 0.4))), 0.025, 4, 143);
		p.Add("Fore", new Cracked(foreMuscle, 1.9, 0.03, 0.07, 144), skin, "Slate", "Fore", 0.035, 2600);
		p.Add("ForeVeins", Grow(foreMuscle, -0.045), fire, "Neon", "Fore", 0.05, 500);
		var spikes = U(0.04,
			Horn(V(0.3, 0.2, 0.05), V(0.42, 0.82, 0.2), V(0.25, 1.3, 0.45), 0.2, 0.02),
			Horn(V(0.62, 0.15, 0.05), V(0.92, 0.42, 0.1), V(1.06, 0.78, 0.3), 0.13, 0.015),
			Horn(V(0.6, -1.1, 0.3), V(0.63, -1.15, 0.72), V(0.58, -1.38, 0.98), 0.14, 0.015));
		p.Add("Spikes", Rgh(spikes, 0.008, 10, 145), RGB(28, 22, 28), "Slate", null, 0.025, 1500);
		var foreSpikes = new Union(0.03);
		for (int i = 0; i < 3; i++)
		{
			double y = -1.45 - i * 0.28;
			foreSpikes.Add(Horn(V(0.98, y, 0.05), V(1.2, y + 0.05, 0.1), V(1.3, y + 0.22, 0.2), 0.08 - i * 0.012, 0.01));
		}
		p.Add("ForeSpikes", foreSpikes, RGB(28, 22, 28), "Slate", "Fore", 0.02, 700);
		// the blades: curved horn shapes flattened into knives
		var blades = new Union(0);
		foreach (double z in new[] { -0.4, 0.0, 0.4 })
			blades.Add(Both(Horn(V(0.7, -2.72, z), V(0.74, -3.55, z - 0.05), V(0.68, -4.35, z - 0.48), 0.15, 0.01), Box(V(0.7, -3.5, 0), V(0.06, 1.3, 1.5), 0.02), 0));
		p.Add("Blades", blades, fire, "Neon", "Fore", 0.018, 1200);
		return p;
	}

	// MAGNETIC CLAW: a yellow hydraulic crane arm - pistons, hinge drums, a bracket, and a big
	// red horseshoe magnet with polished steel poles.
	static PartSpec MagneticClaw()
	{
		var p = new PartSpec("MagneticClaw") { ArmMirror = true };
		p.Group("Fore", V(0.5, -1.0, 0));
		var yellow = RGB(206, 164, 42);
		var grey = RGB(90, 95, 105);
		var upper = U(0.05,
			Box(V(0.38, -0.5, 0), V(0.27, 0.48, 0.28), 0.1, R(0, 0, 10)),
			Box(V(0.38, -0.5, -0.29), V(0.18, 0.3, 0.03), 0.02, R(0, 0, 10)));     // inset panel
		p.Add("Upper", Rgh(upper, 0.006, 7, 151), yellow, "Metal", null, 0.03, 1400);
		var joints = U(0.04,
			Ball(V(0.2, 0, 0), 0.45),
			Ring(V(0.2, 0, 0), 0.4, 0.06, R(0, 0, 90)),
			Cone(V(0.5, -1.0, -0.36), V(0.5, -1.0, 0.36), 0.22, 0.22),               // the elbow drum
			Cone(V(0.25, -0.12, 0.32), V(0.36, -0.55, 0.36), 0.11, 0.1),              // piston housing
			Studs(0.07, V(0.5, -1.0, -0.42), V(0.5, -1.0, 0.42)));
		p.Add("Joints", joints, grey, "Metal", null, 0.025, 1600);
		p.Add("Piston", Cone(V(0.36, -0.55, 0.36), V(0.48, -0.98, 0.34), 0.06, 0.06), RGB(215, 220, 228), "Metal", null, 0.02, 300);
		var fore = U(0.05,
			Box(V(0.55, -1.5, 0), V(0.25, 0.5, 0.26), 0.1, R(0, 0, 10)),
			Box(V(0.6, -2.0, 0), V(0.22, 0.13, 0.22), 0.05));                        // the bracket
		p.Add("Fore", Rgh(fore, 0.006, 7, 152), yellow, "Metal", "Fore", 0.03, 1400);
		// the magnet: a thick horseshoe (cut out in 2D, then rounded off)
		Func<double, double, double> shoe = Flat.Union(
			Flat.Clip(Flat.Minus(Flat.Circle(0.6, -2.55, 0.66), Flat.Circle(0.6, -2.55, 0.28)), (x, y) => -2.55 - y),
			Flat.Poly(-0.06, -2.55, 0.32, -2.55, 0.32, -3.0, -0.06, -3.0),
			Flat.Poly(0.88, -2.55, 1.26, -2.55, 1.26, -3.0, 0.88, -3.0));
		p.Add("Magnet", Grow(new Sheet(shoe, 0.38, 0, 0, -0.2, -3.1, 1.4, -1.8), 0.05), RGB(200, 40, 40), "SmoothPlastic", "Fore", 0.025, 1200);
		Func<double, double, double> poles = Flat.Union(
			Flat.Poly(-0.06, -3.0, 0.32, -3.0, 0.32, -3.2, -0.06, -3.2),
			Flat.Poly(0.88, -3.0, 1.26, -3.0, 1.26, -3.2, 0.88, -3.2));
		p.Add("Poles", Grow(new Sheet(poles, 0.38, 0, 0, -0.2, -3.3, 1.4, -2.9), 0.05), RGB(222, 222, 232), "Metal", "Fore", 0.025, 400);
		return p;
	}

	// TITAN HAMMER ARM: a rusted piston arm torn off the Scrap Titan - layered pauldron, a
	// wrapped haft, and a riveted sledge head banded with iron, both faces glowing.
	static PartSpec TitanHammerArm()
	{
		var p = new PartSpec("TitanHammerArm") { ArmMirror = true };
		p.Group("Fore", V(0.6, -1.1, 0));
		var rust = RGB(112, 80, 60);
		var steel = RGB(70, 70, 80);
		var upper = U(0.06,
			Box(V(0.52, -0.55, 0), V(0.44, 0.56, 0.44), 0.16, R(0, 0, 8)),
			Ring(V(0.5, -0.45, 0), 0.45, 0.06, R(0, 0, 8)),
			Ring(V(0.56, -0.85, 0), 0.43, 0.06, R(0, 0, 8)));
		p.Add("Upper", Rgh(upper, 0.012, 4, 161), rust, "CorrodedMetal", null, 0.035, 2000);
		// the pauldron: two overlapping curved plates over the shoulder ball
		Func<V3, V3, double, Sdf> plate = (c, r, cutY) => Both(Shell(Ell(c, r), 0.09), Box(V(c.X, cutY + 1, 0), V(2, 1, 2), 0), 0.02);
		var joints = U(0.04,
			Ball(V(0.3, 0, 0), 0.55),
			plate(V(0.32, 0.05, 0), V(0.72, 0.62, 0.7), 0.05),
			plate(V(0.52, -0.12, 0), V(0.62, 0.55, 0.66), -0.2),
			Ball(V(0.6, -1.1, 0), 0.45),
			Studs(0.06, V(0.1, 0.62, -0.42), V(0.5, 0.58, -0.45), V(0.88, 0.38, -0.4)));
		p.Add("Joints", Rgh(joints, 0.01, 6, 163), steel, "Metal", null, 0.035, 2200);
		var fore = U(0.06,
			Box(V(0.68, -1.65, 0), V(0.42, 0.56, 0.42), 0.16, R(0, 0, 8)),
			Ring(V(0.7, -1.95, 0), 0.42, 0.06, R(0, 0, 8)));
		p.Add("Fore", Rgh(fore, 0.012, 4, 164), rust, "CorrodedMetal", "Fore", 0.035, 1600);
		var haft = Ribbed(0.25, 0.24, 6, 0.12, V(0.75, -2.0, 0), V(0.75, -2.35, 0), V(0.75, -2.72, 0));
		p.Add("Haft", haft, RGB(55, 55, 62), "Metal", "Fore", 0.025, 900);
		// the head: end recesses for the glowing faces
		Sdf head = Box(V(0.75, -3.3, 0), V(1.2, 0.65, 0.7), 0.14);
		foreach (double x in new[] { 1.95, -0.45 })
			head = Cut(head, Box(V(x, -3.3, 0), V(0.08, 0.48, 0.5), 0.04), 0.02);
		head = Cut(head, Ball(V(1.3, -2.55, -0.85), 0.32), 0.1);     // battle dents
		head = Cut(head, Ball(V(0.1, -4.05, -0.6), 0.28), 0.1);
		p.Add("Head", Rgh(head, 0.006, 4, 166), RGB(80, 82, 92), "DiamondPlate", "Fore", 0.035, 2600);
		var bands = new Union(0.03);
		foreach (double x in new[] { -0.05, 1.55 })
			bands.Add(Cut(Box(V(x, -3.3, 0), V(0.11, 0.72, 0.77), 0.05), Box(V(x, -3.3, 0), V(0.3, 0.62, 0.67), 0), 0));
		bands.Add(Cut(Box(V(0.75, -3.3, 0), V(0.3, 0.72, 0.77), 0.06), Box(V(0.75, -3.3, 0), V(0.5, 0.62, 0.67), 0), 0));
		var rv = new List<V3>();
		foreach (double x in new[] { -0.05, 1.55 })
			foreach (double y in new[] { -2.95, -3.65 }) { rv.Add(V(x, y, -0.79)); rv.Add(V(x, y, 0.79)); }
		bands.Add(Studs(0.06, rv.ToArray()));
		p.Add("Bands", bands, RGB(58, 58, 66), "Metal", "Fore", 0.025, 1800);
		p.Add("Faces", U(0, Box(V(1.91, -3.3, 0), V(0.05, 0.47, 0.49), 0.03), Box(V(-0.41, -3.3, 0), V(0.05, 0.47, 0.49), 0.03)), RGB(255, 140, 40), "Neon", "Fore", 0.03, 200);
		return p;
	}

	// INFERNO GAUNTLET: an arm of cooling basalt split by rivers of lava - an iron pauldron
	// with spikes, a banded iron bracer, and a huge rock fist with iron knuckle spikes.
	static PartSpec InfernoGauntlet()
	{
		var p = new PartSpec("InfernoGauntlet") { ArmMirror = true };
		p.Group("Fore", V(0.6, -1.55, 0));
		var basalt = RGB(92, 70, 64);
		var iron = RGB(130, 100, 84);
		var lava = RGB(255, 110, 30);
		Sdf rock = Rgh(Rgh(U(0.16,
			Ball(V(0.3, 0.05, 0), 0.6),
			Tube(0.42, 0.38, V(0.35, -0.1, 0), V(0.5, -0.85, 0), V(0.6, -1.45, 0)),
			Ball(V(0.42, -0.55, -0.18), 0.32), Ball(V(0.62, -0.95, 0.2), 0.3),
			Ball(V(0.6, -1.55, 0), 0.45)), 0.06, 2.4, 171), 0.02, 7, 172);
		p.Add("Rock", new Cracked(rock, 1.6, 0.045, 0.13, 173), basalt, "Basalt", null, 0.035, 2800);
		p.Add("Magma", Grow(rock, -0.08), lava, "Neon", null, 0.06, 500);
		// an iron shell over the shoulder, spiked
		var pauldron = U(0.05,
			Both(Shell(Ell(V(0.34, 0.12, 0), V(0.74, 0.62, 0.72)), 0.1), Box(V(0.34, 1.1, 0), V(2, 1, 2), 0), 0.02),
			Both(Shell(Ell(V(0.56, -0.05, 0), V(0.62, 0.55, 0.66)), 0.09), Box(V(0.56, 0.85, 0), V(2, 1, 2), 0), 0.02),
			Horn(V(0.6, 0.52, 0), V(0.85, 0.85, 0), V(1.0, 1.15, 0.05), 0.13, 0.015),
			Horn(V(0.35, 0.55, 0.25), V(0.45, 0.85, 0.45), V(0.5, 1.08, 0.72), 0.1, 0.012),
			Horn(V(0.35, 0.55, -0.25), V(0.45, 0.85, -0.45), V(0.5, 1.05, -0.68), 0.1, 0.012));
		p.Add("Pauldron", Rgh(pauldron, 0.012, 6, 174), iron, "Metal", null, 0.03, 1800);
		Sdf bracer = U(0.06,
			Tube(0.46, 0.44, V(0.6, -1.6, 0), V(0.62, -2.1, 0), V(0.62, -2.45, 0)),
			Ring(V(0.62, -1.9, 0), 0.46, 0.06, I),
			Ring(V(0.62, -2.35, 0), 0.45, 0.06, I));
		bracer = Rgh(bracer, 0.012, 6, 175);
		p.Add("Bracer", new Cracked(bracer, 1.8, 0.03, 0.09, 176), iron, "Metal", "Fore", 0.035, 1800);
		Sdf fist = Rgh(Rgh(U(0.12,
			Box(V(0.62, -3.22, 0), V(0.68, 0.6, 0.7), 0.3),
			Studs(0.22, V(0.2, -3.55, -0.6), V(0.48, -3.6, -0.64), V(0.76, -3.6, -0.64), V(1.04, -3.55, -0.6)),  // knuckles
			Ell(V(0.0, -3.05, -0.38), V(0.2, 0.36, 0.26))), 0.05, 2.6, 177), 0.02, 7, 178);                     // thumb
		p.Add("Fist", new Cracked(fist, 1.6, 0.045, 0.13, 179), basalt, "Basalt", "Fore", 0.035, 3000);
		p.Add("ForeMagma", U(0, Grow(fist, -0.08), Grow(bracer, -0.06), Ring(V(0.62, -2.58, 0), 0.47, 0.07, I)), lava, "Neon", "Fore", 0.05, 800);
		var spikes = new Union(0);
		foreach (double x in new[] { 0.34, 0.62, 0.9 })
			spikes.Add(Horn(V(x, -3.58, -0.72), V(x, -3.66, -0.95), V(x, -3.68, -1.12), 0.12, 0.015));
		p.Add("Spikes", spikes, iron, "Metal", "Fore", 0.02, 600);
		return p;
	}

	//======================================================================================
	// LEGS (each leg in its own hip joint's frame; the foot bottoms match the old ones so
	// hip height is unchanged)
	//======================================================================================

	// JELLY LEGS: wobbling translucent goo with a leg bone floating inside it, bubbles and
	// drips, each foot a squashed puddle.
	static PartSpec JellyLegs()
	{
		var p = new PartSpec("JellyLegs");
		p.Group("R", V(0.8, 0, 0));
		p.Group("L", V(-0.8, 0, 0));
		var jelly = Rgh(U(0.3,
			Ball(V(0, -0.45, 0), 0.55),
			Cone(V(0, -0.6, 0), V(0, -2.3, 0), 0.42, 0.4),
			Ball(V(0.05, -1.2, 0), 0.5),
			Ball(V(-0.03, -1.85, 0.02), 0.45),
			Ell(V(0, -2.62, -0.2), V(0.55, 0.28, 0.72)),
			Ball(V(0.45, -2.72, 0.12), 0.13),
			Cone(V(0.3, -1.4, -0.32), V(0.33, -1.9, -0.4), 0.11, 0.06),
			Cone(V(-0.32, -0.9, 0.2), V(-0.35, -1.3, 0.25), 0.1, 0.05)), 0.03, 2.5, 181);
		p.AddPair("Jelly", jelly, RGB(110, 225, 140), "SmoothPlastic", new[] { "R" }, new[] { "L" }, true, 0.04, 2200, 0.35);
		var bone = U(0.08,
			Tube(0.1, 0.09, V(0, -0.3, 0), V(0, -1.4, 0.02)),
			Studs(0.15, V(0, -0.25, 0), V(0, -1.5, 0.02)),
			Tube(0.09, 0.08, V(0, -1.55, 0.02), V(0, -2.45, -0.05)),
			Ell(V(0, -2.55, -0.2), V(0.18, 0.08, 0.32)));
		p.AddPair("Bone", bone, RGB(225, 230, 205), "SmoothPlastic", new[] { "R" }, new[] { "L" }, true, 0.025, 900);
		var bubbles = Studs(0.06, V(0.2, -0.6, -0.2), V(-0.18, -1.1, 0.15), V(0.15, -1.7, -0.1), V(-0.1, -2.2, 0.15), V(0.25, -2.55, -0.45), V(-0.2, -0.35, 0.1));
		p.AddPair("Bubbles", bubbles, RGB(190, 255, 205), "Neon", new[] { "R" }, new[] { "L" }, true, 0.02, 400, 0.3);
		return p;
	}

	// DRIFTING WISP: a glowing soul-flame with a bright heart, its tail twisting into two
	// thinning strands, embers orbiting it.
	static PartSpec DriftingWisp()
	{
		var p = new PartSpec("DriftingWisp");
		Func<double, double, double, double, V3[]> strand = (phase, r0, top, bottom) =>
		{
			var pts = new V3[9];
			for (int i = 0; i < 9; i++)
			{
				double t = i / 8.0, a = phase + t * Math.PI * 3.2, r = r0 * (1 - t) + 0.04;
				pts[i] = V(Math.Cos(a) * r, top + (bottom - top) * t, Math.Sin(a) * r);
			}
			return pts;
		};
		var body = Rgh(U(0.22,
			Ball(V(0, -0.7, 0), 0.62),
			Shapes.Path(strand(0, 0.32, -0.85, -2.25), 0.42, 0.04),
			Shapes.Path(strand(Math.PI, 0.25, -0.95, -2.0), 0.26, 0.03)), 0.05, 3, 191);
		var b = p.Add("Wisp", body, RGB(150, 220, 255), "Neon", null, 0.035, 2200);
		b.Transparency = 0.35;
		p.Add("Heart", Ball(V(0, -0.65, 0), 0.4), RGB(225, 248, 255), "Neon", null, 0.03, 300);
		p.Add("Embers", Studs(0.07, V(0.85, -0.4, 0.2), V(-0.7, -1.0, -0.45), V(0.4, -1.6, -0.6), V(-0.55, -0.3, 0.6), V(0.6, -1.25, 0.55)), RGB(200, 240, 255), "Neon", null, 0.02, 300);
		return p;
	}

	// PHANTOM LEGS: spectral plate armour - greaves, knee cops with glowing orbs, pointed
	// sabatons with heel spurs, ghost-light trailing off the backs of the legs.
	static PartSpec PhantomLegs()
	{
		var p = new PartSpec("PhantomLegs");
		p.Group("R", V(0.85, 0, 0));
		p.Group("L", V(-0.85, 0, 0));
		var phantom = RGB(150, 120, 230);
		var armour = Rgh(U(0.06,
			Ell(V(0, -0.78, 0), V(0.38, 0.78, 0.4)),
			Cone(V(0, -0.15, -0.34), V(0, -1.35, -0.3), 0.07, 0.06),                  // thigh ridge
			Ball(V(0, -1.55, -0.1), 0.3),                                               // knee cop
			Ell(V(0, -1.55, -0.28), V(0.34, 0.24, 0.1)),
			Cone(V(0, -1.62, 0.08), V(0, -3.05, 0.1), 0.3, 0.23),                       // shin greave
			Cone(V(0, -1.85, -0.2), V(0, -2.95, -0.13), 0.06, 0.05),
			Ell(V(0, -3.25, 0.0), V(0.3, 0.25, 0.36)),                                  // sabaton
			Cone(V(0, -3.3, 0.05), V(0, -3.4, -0.78), 0.26, 0.07),
			Cone(V(0, -3.22, 0.3), V(0, -3.28, 0.62), 0.07, 0.01)), 0.01, 6, 201);      // spur
		p.AddPair("Armour", armour, phantom, "SmoothPlastic", new[] { "R" }, new[] { "L" }, true, 0.03, 2600, 0.3);
		var glow = U(0,
			Ball(V(0, -1.55, -0.38), 0.14),
			Ring(V(0, -3.0, 0.1), 0.25, 0.04, I),
			Ring(V(0, -0.35, 0), 0.33, 0.035, I));
		p.AddPair("Glow", glow, RGB(200, 160, 255), "Neon", new[] { "R" }, new[] { "L" }, true, 0.02, 600);
		var wisps = Rgh(U(0.1,
			Tube(0.24, 0.02, V(0, -0.25, 0.3), V(0.05, -0.8, 0.62), V(-0.05, -1.4, 0.88), V(0, -1.95, 1.08)),
			Tube(0.18, 0.02, V(0, -1.7, 0.25), V(0.03, -2.2, 0.55), V(-0.02, -2.7, 0.72))), 0.04, 3, 202);
		p.AddPair("Wisps", wisps, phantom, "Neon", new[] { "R" }, new[] { "L" }, true, 0.03, 900, 0.6);
		return p;
	}

	// SCRAP LEGS: flanged exhaust pipes bolted together - a hex-nut knee, dented and pitted
	// pipes, and heavy riveted iron boots with toe caps.
	static PartSpec ScrapLegs()
	{
		var p = new PartSpec("ScrapLegs");
		p.Group("R", V(0.85, 0, 0));
		p.Group("L", V(-0.85, 0, 0));
		Sdf pipes = U(0.04,
			Cone(V(0, 0.0, 0), V(0, -1.42, 0), 0.34, 0.33),
			Cone(V(0, -1.86, 0), V(0, -2.92, 0), 0.27, 0.27),
			Ring(V(0, -0.75, 0), 0.35, 0.05, I));
		pipes = Cut(pipes, Ball(V(0.3, -0.45, -0.4), 0.2), 0.08);
		pipes = Cut(pipes, Ball(V(-0.25, -2.3, -0.35), 0.16), 0.08);
		p.AddPair("Pipes", Rgh(pipes, 0.012, 4, 211), RGB(105, 90, 75), "CorrodedMetal", new[] { "R" }, new[] { "L" }, true, 0.03, 2000);
		var bolts = U(0.03,
			new Crystal(V(-0.3, -1.65, 0), V(1, 0, 0), 0.4, 0.6, 0.001, 0),           // the knee nut
			Cone(V(-0.42, -1.65, 0), V(0.42, -1.65, 0), 0.13, 0.13),
			Ring(V(0, -0.06, 0), 0.36, 0.07, I), Ring(V(0, -1.38, 0), 0.36, 0.07, I),
			Ring(V(0, -1.9, 0), 0.29, 0.06, I), Ring(V(0, -2.86, 0), 0.29, 0.06, I));
		p.AddPair("Bolts", Rgh(bolts, 0.006, 8, 213), RGB(150, 150, 160), "Metal", new[] { "R" }, new[] { "L" }, true, 0.025, 1600);
		Sdf boot = U(0.06,
			Box(V(0, -3.12, -0.22), V(0.48, 0.2, 0.72), 0.1),
			Ell(V(0, -3.04, -0.74), V(0.46, 0.26, 0.3)),
			Box(V(0, -2.9, 0.05), V(0.38, 0.18, 0.38), 0.08),
			Studs(0.05, V(0.49, -3.05, -0.5), V(0.49, -3.05, 0.1), V(-0.49, -3.05, -0.5), V(-0.49, -3.05, 0.1)));
		for (int i = 0; i < 4; i++)
			boot = Cut(boot, Box(V(0, -3.33, -0.75 + i * 0.35), V(0.6, 0.04, 0.06), 0.01), 0.01);   // tread
		p.AddPair("Boot", Rgh(boot, 0.01, 6, 214), RGB(60, 60, 66), "Metal", new[] { "R" }, new[] { "L" }, true, 0.03, 1600);
		return p;
	}

	// MANGY HOUND LEGS: shaggy digitigrade legs, fur sticking out in clumps, padded paws with
	// four toes and hooked black claws.
	static PartSpec MangyHoundLegs()
	{
		var p = new PartSpec("MangyHoundLegs");
		p.Group("FR", V(1.1, 0, -1.0)); p.Group("FL", V(-1.1, 0, -1.0));
		p.Group("BR", V(1.1, 0, 1.0)); p.Group("BL", V(-1.1, 0, 1.0));
		var leg = U(0.12,
			Ell(V(0, -0.3, 0.05), V(0.36, 0.5, 0.42)),
			Tube(0.36, 0.19, V(0, 0.05, 0), V(0, -0.55, 0.1), V(0.02, -1.1, -0.02), V(0, -1.42, -0.08)));
		var rnd = new Random(221);
		for (int i = 0; i < 14; i++)
		{
			double a = i * Math.PI * 2 / 7 + rnd.NextDouble() * 0.5, y = -0.15 - (i / 7) * 0.45 - rnd.NextDouble() * 0.2;
			double r = i < 7 ? 0.38 : 0.3;
			V3 at = V(Math.Cos(a) * r * 0.9, y, Math.Sin(a) * r * 0.9 + 0.05);
			V3 tip = at + V(Math.Cos(a) * 0.12, -0.32, Math.Sin(a) * 0.12 + 0.1);
			leg.Add(Cone(at, tip, 0.09, 0.012));
		}
		p.AddPair("Fur", Rgh(leg, 0.05, 6, 222), RGB(120, 90, 60), "Fabric", new[] { "FR", "BR" }, new[] { "FL", "BL" }, true, 0.03, 2400);
		var paw = U(0.08,
			Ell(V(0, -1.55, -0.15), V(0.4, 0.2, 0.48)),
			Studs(0.13, V(-0.27, -1.6, -0.56), V(-0.09, -1.6, -0.62), V(0.09, -1.6, -0.62), V(0.27, -1.6, -0.56)));
		p.AddPair("Paw", Rgh(paw, 0.02, 6, 223), RGB(70, 50, 35), "Fabric", new[] { "FR", "BR" }, new[] { "FL", "BL" }, true, 0.025, 1200);
		var claws = new Union(0);
		foreach (double x in new[] { -0.27, -0.09, 0.09, 0.27 })
		{
			double z = Math.Abs(x) > 0.2 ? -0.64 : -0.7;
			claws.Add(Horn(V(x, -1.6, z), V(x, -1.62, z - 0.14), V(x, -1.73, z - 0.2), 0.05, 0.008));
		}
		p.AddPair("Claws", claws, RGB(42, 36, 32), "SmoothPlastic", new[] { "FR", "BR" }, new[] { "FL", "BL" }, true, 0.015, 500);
		return p;
	}

	// VENOMOUS SPIDER LEGS: long jointed chitin legs, knees high, bristles along them, glowing
	// venom bands and a dripping glowing claw at each tip.
	static PartSpec VenomousSpiderLegs()
	{
		var p = new PartSpec("VenomousSpiderLegs");
		p.Group("FR", V(1.0, 0.2, -0.8)); p.Group("FL", V(-1.0, 0.2, -0.8));
		p.Group("BR", V(1.0, 0.2, 0.8)); p.Group("BL", V(-1.0, 0.2, 0.8));
		var pts = new[] { V(0, 0, 0), V(0.55, 0.42, 0), V(1.15, 0.82, 0), V(1.3, 0.6, 0), V(1.42, -0.5, 0), V(1.6, -2.0, 0) };
		var leg = U(0.05,
			Ribbed(0.17, 0.06, 6, 0.12, pts),
			Ball(V(0.05, 0, 0), 0.2), Ball(V(1.18, 0.8, 0), 0.17), Ball(V(1.4, -0.4, 0), 0.11));
		var s = Shapes.Spline(pts, 8);
		for (int i = 2; i < s.Count - 4; i += 3)
		{
			V3 tan = (s[i + 1] - s[i - 1]).Unit();
			V3 side = tan.Cross(V(0, 0, 1)).Unit();
			double r = 0.17 + (0.06 - 0.17) * i / (s.Count - 1.0);
			leg.Add(Cone(s[i] + side * r * 0.7, s[i] + side * (r + 0.16) - tan * 0.08, 0.035, 0.005));
		}
		p.AddPair("Chitin", Rgh(leg, 0.008, 8, 231), RGB(40, 25, 50), "Slate", new[] { "FR", "BR" }, new[] { "FL", "BL" }, true, 0.022, 2400);
		var venom = U(0,
			Ball(V(1.61, -2.08, 0), 0.12),
			Horn(V(1.6, -2.0, 0), V(1.65, -2.18, -0.02), V(1.58, -2.32, -0.09), 0.06, 0.008),
			Ring(V(1.47, -0.95, 0), 0.105, 0.03, R(0, 0, 6.6)),
			Ring(V(1.52, -1.35, 0), 0.095, 0.03, R(0, 0, 6.6)),
			Ring(V(1.56, -1.7, 0), 0.085, 0.028, R(0, 0, 6.6)));
		p.AddPair("Venom", venom, RGB(120, 255, 90), "Neon", new[] { "FR", "BR" }, new[] { "FL", "BL" }, true, 0.015, 700);
		return p;
	}

	//======================================================================================
	// BACK (each wing in its own joint frame: x out along the wing, y up)
	//======================================================================================

	// TINY BAT WINGS: proper little bat wings - an arm bone along the top, a thumb hook at the
	// wrist, three finger bones, a thin membrane scalloped between them.
	static PartSpec TinyBatWings()
	{
		var p = new PartSpec("TinyBatWings");
		p.Group("R", V(0.3, 0.2, 0.1), V(0, -20, 15));
		p.Group("L", V(-0.3, 0.2, 0.1), V(0, 20, -15));
		double[] poly = { 0.05, 0.5, 1.0, 0.6, 1.8, 0.35, 1.65, -0.3, 1.15, -0.6, 0.05, -0.35 };
		var membrane = Flat.Minus(Flat.Poly(poly),
			Flat.Scallop(1.8, 0.35, 1.65, -0.3, 0.1, 0.8, 0),
			Flat.Scallop(1.65, -0.3, 1.15, -0.6, 0.13, 0.8, 0),
			Flat.Scallop(1.15, -0.6, 0.05, -0.35, 0.14, 0.8, 0));
		p.AddPair("Membrane", Rgh(new Sheet(membrane, 0.06, 0.1, 0, 0, -0.7, 1.9, 0.7), 0.008, 8, 241), RGB(62, 40, 78), "SmoothPlastic", new[] { "R" }, new[] { "L" }, true, 0.018, 1800);
		var bones = U(0.04,
			Tube(0.09, 0.06, V(0, 0.5, 0), V(0.5, 0.6, 0), V(1.0, 0.62, 0)),
			Ball(V(1.0, 0.62, 0), 0.08),
			Horn(V(1.0, 0.66, 0), V(1.06, 0.82, -0.02), V(0.95, 0.92, -0.06), 0.045, 0.006),
			Tube(0.045, 0.018, V(1.0, 0.62, 0), V(1.42, 0.55, 0), V(1.8, 0.35, 0)),
			Tube(0.045, 0.018, V(1.0, 0.62, 0), V(1.38, 0.15, 0), V(1.65, -0.3, 0)),
			Tube(0.04, 0.018, V(1.0, 0.62, 0), V(1.12, 0.0, 0), V(1.15, -0.6, 0)));
		p.AddPair("Bones", bones, RGB(35, 25, 40), "SmoothPlastic", new[] { "R" }, new[] { "L" }, true, 0.016, 1200);
		return p;
	}

	// VOID WINGS: great tattered demon wings - torn membrane between long finger bones, veins
	// of violet light running through it, glowing claws on every finger, a spined mount.
	static PartSpec VoidWings()
	{
		var p = new PartSpec("VoidWings");
		p.Group("R", V(0.4, 0.3, 0.2), V(0, -25, 18));
		p.Group("L", V(-0.4, 0.3, 0.2), V(0, 25, -18));
		var wrist = V(2.0, 1.2, 0);
		double[] poly = { 0.05, 0.9, 2.0, 1.2, 3.45, 0.95, 3.35, -0.15, 2.85, -1.05, 1.9, -1.15, 0.1, -0.6 };
		var membrane = Flat.Ragged(Flat.Minus(Flat.Poly(poly),
			Flat.Scallop(3.45, 0.95, 3.35, -0.15, 0.16, 1.5, 0),
			Flat.Scallop(3.35, -0.15, 2.85, -1.05, 0.2, 1.5, 0),
			Flat.Scallop(2.85, -1.05, 1.9, -1.15, 0.22, 1.5, 0),
			Flat.Scallop(1.9, -1.15, 0.1, -0.6, 0.25, 1.5, 0),
			Flat.Circle(0.65, -0.12, 0.08), Flat.Circle(2.35, 0.12, 0.12), Flat.Circle(1.55, -0.72, 0.07), Flat.Circle(3.0, -0.48, 0.09)), 0.03, 6, 251);
		p.AddPair("Membrane", new Sheet(membrane, 0.07, 0.12, 0, 0, -1.3, 3.6, 1.3), RGB(26, 12, 46), "SmoothPlastic", new[] { "R" }, new[] { "L" }, true, 0.02, 3000);
		var bones = U(0.05,
			Tube(0.13, 0.08, V(0, 0.85, 0), V(1.0, 1.15, 0), wrist),
			Ball(wrist, 0.12),
			Tube(0.07, 0.03, wrist, V(2.75, 1.15, 0), V(3.45, 0.95, 0)),
			Tube(0.07, 0.03, wrist, V(2.8, 0.45, 0), V(3.35, -0.15, 0)),
			Tube(0.065, 0.03, wrist, V(2.5, 0.05, 0), V(2.85, -1.05, 0)),
			Tube(0.06, 0.03, wrist, V(2.0, 0.0, 0), V(1.9, -1.15, 0)),
			Horn(V(2.05, 1.28, 0), V(2.2, 1.55, -0.05), V(2.05, 1.72, -0.12), 0.07, 0.01));
		p.AddPair("Bones", Rgh(bones, 0.008, 8, 252), RGB(36, 26, 52), "Slate", new[] { "R" }, new[] { "L" }, true, 0.02, 2000);
		var veins = U(0.02,
			Tube(0.05, 0.03, V(0.3, 0.6, 0), V(1.2, 0.3, 0), V(2.2, -0.2, 0), V(2.75, -0.85, 0)),
			Tube(0.045, 0.03, V(0.4, 0.2, 0), V(1.2, -0.3, 0), V(1.85, -0.95, 0)),
			Tube(0.04, 0.03, V(1.2, 0.3, 0), V(2.0, 0.6, 0), V(3.2, 0.3, 0)),
			Tube(0.035, 0.025, V(2.2, -0.2, 0), V(2.7, -0.3, 0), V(3.1, -0.3, 0)),
			Tube(0.035, 0.025, V(1.2, -0.3, 0), V(0.9, -0.62, 0)),
			Horn(V(3.45, 0.95, 0), V(3.62, 0.95, 0), V(3.72, 0.84, -0.03), 0.045, 0.006),
			Horn(V(3.35, -0.15, 0), V(3.5, -0.25, 0), V(3.55, -0.4, -0.03), 0.045, 0.006),
			Horn(V(2.85, -1.05, 0), V(2.92, -1.2, 0), V(2.85, -1.32, -0.03), 0.045, 0.006),
			Horn(V(1.9, -1.15, 0), V(1.92, -1.3, 0), V(1.82, -1.4, -0.03), 0.04, 0.006));
		p.AddPair("Veins", veins, RGB(170, 90, 255), "Neon", new[] { "R" }, new[] { "L" }, true, 0.016, 1600);
		var mount = U(0.06,
			Ell(V(0, 0.2, 0.15), V(0.45, 0.42, 0.25)),
			Horn(V(0, 0.45, 0.25), V(0, 0.8, 0.42), V(0, 0.95, 0.7), 0.1, 0.012),
			Mx(Horn(V(0.22, 0.4, 0.25), V(0.3, 0.65, 0.42), V(0.32, 0.75, 0.62), 0.07, 0.01)));
		p.Add("Mount", Rgh(mount, 0.01, 7, 253), RGB(30, 20, 45), "Slate", null, 0.025, 1200);
		return p;
	}

	// PHOENIX WINGS: a firebird's wings - primary feathers fanned off the hand, secondaries
	// hanging off the arm, coverts layered over their roots, deep red to gold, the longest
	// feathers' tips burning.
	static PartSpec PhoenixWings()
	{
		var p = new PartSpec("PhoenixWings");
		p.Group("R", V(0.4, 0.3, 0.2), V(0, -22, 16));
		p.Group("L", V(-0.4, 0.3, 0.2), V(0, 22, -16));
		// (root x, root y, angle, length) for each feather
		double[,] prim = { { 2.6, 0.72, 12, 1.25 }, { 2.5, 0.71, 6, 1.3 }, { 2.4, 0.7, 0, 1.35 }, { 2.3, 0.68, -6, 1.4 }, { 2.2, 0.67, -12, 1.45 }, { 2.1, 0.655, -18, 1.48 },
			{ 2.0, 0.64, -25, 1.5 }, { 1.9, 0.63, -31, 1.52 }, { 1.8, 0.62, -38, 1.55 }, { 1.7, 0.61, -44, 1.58 }, { 1.6, 0.6, -50, 1.6 } };
		double[,] sec = { { 1.45, 0.57, -62, 1.55 }, { 1.3, 0.545, -65, 1.55 }, { 1.15, 0.52, -68, 1.55 }, { 1.0, 0.49, -70, 1.52 }, { 0.85, 0.46, -73, 1.5 },
			{ 0.7, 0.43, -75, 1.48 }, { 0.55, 0.4, -78, 1.45 }, { 0.4, 0.37, -80, 1.4 }, { 0.25, 0.33, -83, 1.35 } };
		var prims = new List<Func<double, double, double>>();
		var tips = new List<Func<double, double, double>>();
		for (int i = 0; i < prim.GetLength(0); i++)
		{
			double x = prim[i, 0], y = prim[i, 1], a = prim[i, 2], l = prim[i, 3], ar = a * Math.PI / 180;
			prims.Add(Flat.Leaf(x, y, a, l, 0.16));
			if (i < 7) tips.Add(Flat.Leaf(x + Math.Cos(ar) * l * 0.7, y + Math.Sin(ar) * l * 0.7, a, l * 0.3, 0.1));
		}
		var secs = new List<Func<double, double, double>>();
		for (int i = 0; i < sec.GetLength(0); i++)
			secs.Add(Flat.Leaf(sec[i, 0], sec[i, 1], sec[i, 2], sec[i, 3], 0.17));
		var coverts = new List<Func<double, double, double>>();
		for (int i = 0; i < 8; i++)
		{
			double t = i / 7.0;
			coverts.Add(Flat.Leaf(0.2 + t * 2.3, 0.33 + t * 0.38, -45 + t * 25, 0.75, 0.13));
		}
		p.AddPair("Primaries", Rgh(new Sheet(Flat.Union(prims.ToArray()), 0.06, 0.1, 0, 1.3, -1.0, 4.0, 1.2), 0.006, 9, 261), RGB(255, 186, 48), "SmoothPlastic", new[] { "R" }, new[] { "L" }, true, 0.018, 2600);
		p.AddPair("Secondaries", Rgh(new Sheet(Flat.Union(secs.ToArray()), 0.06, 0.1, 0.05, 0.0, -1.25, 2.4, 0.8), 0.006, 9, 262), RGB(240, 112, 30), "SmoothPlastic", new[] { "R" }, new[] { "L" }, true, 0.018, 2200);
		p.AddPair("Coverts", Rgh(new Sheet(Flat.Union(coverts.ToArray()), 0.06, 0.1, 0.1, 0.0, -0.5, 3.1, 1.0), 0.006, 9, 263), RGB(200, 48, 20), "SmoothPlastic", new[] { "R" }, new[] { "L" }, true, 0.018, 1800);
		p.AddPair("Flames", new Sheet(Flat.Union(tips.ToArray()), 0.085, 0.1, 0, 2.6, -0.5, 4.0, 1.2), RGB(255, 222, 92), "Neon", new[] { "R" }, new[] { "L" }, true, 0.016, 600);
		var arm = Ribbed(0.11, 0.05, 9, 0.08, V(0, 0.25, 0.06), V(0.8, 0.45, 0.08), V(1.6, 0.6, 0.08), V(2.65, 0.73, 0.06));
		p.AddPair("Arm", Rgh(arm, 0.008, 8, 264), RGB(150, 30, 20), "SmoothPlastic", new[] { "R" }, new[] { "L" }, true, 0.02, 1000);
		var mount = U(0.08,
			Ell(V(0, 0.2, 0.15), V(0.45, 0.45, 0.32)),
			Horn(V(0, 0.5, 0.2), V(0, 0.82, 0.32), V(0, 0.95, 0.55), 0.12, 0.012),
			Mx(Horn(V(0.2, 0.45, 0.2), V(0.28, 0.7, 0.3), V(0.3, 0.8, 0.5), 0.09, 0.01)));
		p.Add("Mount", mount, RGB(170, 40, 20), "SmoothPlastic", null, 0.025, 1000);
		return p;
	}

	//======================================================================================
	// TAILS (the joint at the core's lower back, extending backward, +Z)
	//======================================================================================

	// BENT METAL TAIL: a length of flanged exhaust pipe kinked to one side, clamps round it,
	// dented, ending in a torn, sharpened blade of sheet metal.
	static PartSpec BentMetalTail()
	{
		var p = new PartSpec("BentMetalTail");
		var pts = new[] { V(0, -0.05, 0), V(0, -0.1, 0.9), V(0.2, -0.3, 1.7), V(0.45, -0.45, 2.4), V(0.6, -0.52, 2.85) };
		Sdf pipe = Shapes.Path(pts, 0.32, 0.22, 8, 5, 0.06);
		pipe = Cut(pipe, Ball(V(0.35, 0.1, 1.2), 0.22), 0.08);
		pipe = Cut(pipe, Cone(V(0.6, -0.52, 2.8), V(0.68, -0.55, 3.1), 0.14, 0.14), 0.02);   // the open end
		p.Add("Pipe", Rgh(pipe, 0.006, 4, 271), RGB(110, 115, 125), "Metal", null, 0.03, 2200);
		var s = Shapes.Spline(pts, 8);
		var clamps = new Union(0);
		foreach (int i in new[] { 4, 13, 22, 29 })
		{
			V3 tan = (s[i + 1] - s[i - 1]).Unit();
			// tilt a ring (axis Y) onto the pipe's direction
			double pitch = Math.Atan2(tan.Z, tan.Y) * 180 / Math.PI, yaw = Math.Atan2(tan.X, Math.Sqrt(tan.Y * tan.Y + tan.Z * tan.Z)) * 180 / Math.PI;
			double t = (double)i / (s.Count - 1);
			clamps.Add(Ring(s[i], 0.32 + (0.22 - 0.32) * Math.Pow(t, 0.9) - 0.005, 0.065, R(pitch, 0, -yaw)));
		}
		p.Add("Clamps", clamps, RGB(70, 72, 82), "Metal", null, 0.02, 1400);
		// two cones flattened into a blade standing upright along the tail's line
		var blade = Both(U(0.05,
			Cone(V(0.5, -0.5, 2.55), V(1.0, -0.68, 3.55), 0.3, 0.02),
			Cone(V(0.55, -0.4, 2.65), V(0.82, -0.12, 3.25), 0.18, 0.01)), Box(V(0.72, -0.45, 3.05), V(0.05, 1.0, 1.0), 0.02, R(0, 26.6, 0)), 0);
		p.Add("Blade", Rgh(blade, 0.01, 7, 273), RGB(172, 176, 186), "Metal", null, 0.018, 900);
		return p;
	}

	// SCORPION TAIL: armoured segments curling up over the back, each with a ridge spike and
	// overlapping plates, a bulging venom sac glowing green and a hooked black stinger.
	static PartSpec ScorpionTail()
	{
		var p = new PartSpec("ScorpionTail");
		var centres = new[] { V(0, -0.1, 0.55), V(0, 0.25, 1.3), V(0, 0.95, 1.9), V(0, 1.8, 2.15), V(0, 2.65, 2.0), V(0, 3.35, 1.5), V(0, 3.75, 0.85) };
		var mid = V(0, 1.9, 0.9);
		var plates = new Union(0.03);
		var joints = new Union(0.05);
		for (int i = 0; i < centres.Length; i++)
		{
			V3 c = centres[i];
			V3 tan = (centres[Math.Min(i + 1, centres.Length - 1)] - centres[Math.Max(i - 1, 0)]).Unit();
			double ang = Math.Atan2(-tan.Y, tan.Z) * 180 / Math.PI;
			double r = 0.44 - i * 0.03;
			V3 outv = (c - mid); outv = V(0, outv.Y, outv.Z).Unit();
			// a segment: an armoured shell longer than the gap to the next, so they overlap
			// like plates, its rim flared, a raised plate down its back
			plates.Add(Ell(c, V(r * 0.95, r * 0.78, r * 1.3), R(ang, 0, 0)));
			plates.Add(Ell(c - tan * (r * 0.45), V(r * 1.02, r * 0.86, r * 0.35), R(ang, 0, 0)));
			plates.Add(Ell(c + outv * (r * 0.38), V(r * 0.62, r * 0.5, r * 1.05), R(ang, 0, 0)));
			plates.Add(Cone(c + outv * (r * 0.7), c + outv * (r + 0.22) - tan * 0.12, 0.08, 0.01));  // ridge spike
			if (i < centres.Length - 1) joints.Add(Ball((c + centres[i + 1]) * 0.5, r * 0.62));
		}
		p.Add("Plates", Rgh(plates, 0.008, 5, 281), RGB(104, 74, 42), "Slate", null, 0.03, 3600);
		p.Add("Joints", Rgh(joints, 0.01, 6, 283), RGB(52, 36, 22), "Slate", null, 0.03, 1000);
		var sac = Rgh(U(0.12, Ell(V(0, 3.85, 0.22), V(0.3, 0.34, 0.4), R(20, 0, 0)), Ball(V(0, 3.82, 0.55), 0.22)), 0.015, 5, 284);
		p.Add("Venom", sac, RGB(120, 220, 70), "Neon", null, 0.025, 800);
		p.Add("Stinger", Horn(V(0, 3.75, -0.05), V(0, 3.75, -0.5), V(0, 3.3, -0.62), 0.16, 0.012), RGB(26, 24, 26), "Slate", null, 0.02, 600);
		return p;
	}
}
