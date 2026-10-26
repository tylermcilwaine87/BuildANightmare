// MeshForge: sculpts Nightmare part meshes from signed distance fields (SDFs) and writes
// them as OBJ files for Roblox Studio's 3D importer, plus a JSON preview for the browser.
//
// A part is a set of named MESHES (one per colour / material: skin, bone, eyes...). Each
// mesh is an SDF: rounded primitives blended together (smooth union), carved (smooth
// subtract) and roughened with a little noise, so it reads as one sculpted organic form
// instead of stacked blocks. The surface is extracted with Surface Nets (smooth, no seams)
// and shaded with the SDF gradient as its normals.
//
// Coordinates: studs, in the PART's own frame exactly as PartDefinitions authors pieces
// (+X right, +Y up, -Z forward). A mesh in a joint group (a jaw, a forearm) is authored in
// the part frame too; the Luau table it writes gives its position relative to the group's
// pivot.
//
// Build:  csc /nologo /optimize /out:Forge.exe Forge.cs Parts.cs
// Run:    Forge.exe <outDir> [partName ...]
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;

public struct V3
{
	public double X, Y, Z;
	public V3(double x, double y, double z) { X = x; Y = y; Z = z; }
	public static V3 operator +(V3 a, V3 b) { return new V3(a.X + b.X, a.Y + b.Y, a.Z + b.Z); }
	public static V3 operator -(V3 a, V3 b) { return new V3(a.X - b.X, a.Y - b.Y, a.Z - b.Z); }
	public static V3 operator *(V3 a, double s) { return new V3(a.X * s, a.Y * s, a.Z * s); }
	public static V3 operator *(double s, V3 a) { return a * s; }
	public static V3 operator -(V3 a) { return new V3(-a.X, -a.Y, -a.Z); }
	public double Dot(V3 b) { return X * b.X + Y * b.Y + Z * b.Z; }
	public V3 Cross(V3 b) { return new V3(Y * b.Z - Z * b.Y, Z * b.X - X * b.Z, X * b.Y - Y * b.X); }
	public double Len() { return Math.Sqrt(X * X + Y * Y + Z * Z); }
	public V3 Unit() { double l = Len(); return l > 1e-12 ? this * (1 / l) : new V3(0, 1, 0); }
	public V3 Mul(V3 b) { return new V3(X * b.X, Y * b.Y, Z * b.Z); }
	public V3 Abs() { return new V3(Math.Abs(X), Math.Abs(Y), Math.Abs(Z)); }
	public static V3 Lerp(V3 a, V3 b, double t) { return a + (b - a) * t; }
}

// Rotation by Euler degrees, applied like Roblox's CFrame.Angles(x, y, z) (X then Y then Z on
// the vector's left: R = Rx * Ry * Rz).
public struct Rot
{
	public double[] M;
	public static Rot Deg(double x, double y, double z)
	{
		double cx = Math.Cos(x * Math.PI / 180), sx = Math.Sin(x * Math.PI / 180);
		double cy = Math.Cos(y * Math.PI / 180), sy = Math.Sin(y * Math.PI / 180);
		double cz = Math.Cos(z * Math.PI / 180), sz = Math.Sin(z * Math.PI / 180);
		double[] rx = { 1, 0, 0, 0, cx, -sx, 0, sx, cx };
		double[] ry = { cy, 0, sy, 0, 1, 0, -sy, 0, cy };
		double[] rz = { cz, -sz, 0, sz, cz, 0, 0, 0, 1 };
		return new Rot { M = Mul(Mul(rx, ry), rz) };
	}
	static double[] Mul(double[] a, double[] b)
	{
		var r = new double[9];
		for (int i = 0; i < 3; i++)
			for (int j = 0; j < 3; j++)
				r[i * 3 + j] = a[i * 3] * b[j] + a[i * 3 + 1] * b[3 + j] + a[i * 3 + 2] * b[6 + j];
		return r;
	}
	public V3 Apply(V3 v) { return new V3(M[0] * v.X + M[1] * v.Y + M[2] * v.Z, M[3] * v.X + M[4] * v.Y + M[5] * v.Z, M[6] * v.X + M[7] * v.Y + M[8] * v.Z); }
	// inverse = transpose
	public V3 Inverse(V3 v) { return new V3(M[0] * v.X + M[3] * v.Y + M[6] * v.Z, M[1] * v.X + M[4] * v.Y + M[7] * v.Z, M[2] * v.X + M[5] * v.Y + M[8] * v.Z); }
}

public abstract class Sdf
{
	public abstract double D(V3 p);
	// rough bounds (for the sampling grid)
	public abstract void Bounds(ref V3 lo, ref V3 hi);
	protected static void Grow(ref V3 lo, ref V3 hi, V3 c, double r)
	{
		lo = new V3(Math.Min(lo.X, c.X - r), Math.Min(lo.Y, c.Y - r), Math.Min(lo.Z, c.Z - r));
		hi = new V3(Math.Max(hi.X, c.X + r), Math.Max(hi.Y, c.Y + r), Math.Max(hi.Z, c.Z + r));
	}
}

public class Sphere : Sdf
{
	V3 c; double r;
	public Sphere(V3 c, double r) { this.c = c; this.r = r; }
	public override double D(V3 p) { return (p - c).Len() - r; }
	public override void Bounds(ref V3 lo, ref V3 hi) { Grow(ref lo, ref hi, c, r); }
}

// Ellipsoid (approximate distance, good enough for blending), optionally rotated.
public class Ellipsoid : Sdf
{
	V3 c, r; Rot rot;
	public Ellipsoid(V3 c, V3 radii, Rot rot) { this.c = c; this.r = radii; this.rot = rot; }
	public Ellipsoid(V3 c, V3 radii) : this(c, radii, Rot.Deg(0, 0, 0)) { }
	public override double D(V3 p)
	{
		V3 q = rot.Inverse(p - c);
		double k0 = new V3(q.X / r.X, q.Y / r.Y, q.Z / r.Z).Len();
		double k1 = new V3(q.X / (r.X * r.X), q.Y / (r.Y * r.Y), q.Z / (r.Z * r.Z)).Len();
		return k1 > 1e-9 ? k0 * (k0 - 1) / k1 : -Math.Min(r.X, Math.Min(r.Y, r.Z));
	}
	public override void Bounds(ref V3 lo, ref V3 hi) { Grow(ref lo, ref hi, c, Math.Max(r.X, Math.Max(r.Y, r.Z))); }
}

// Round cone: a capsule whose radius tapers from ra (at a) to rb (at b).
public class RoundCone : Sdf
{
	V3 a, b; double ra, rb;
	public RoundCone(V3 a, V3 b, double ra, double rb) { this.a = a; this.b = b; this.ra = ra; this.rb = rb; }
	// (exact round-cone distance, after Inigo Quilez)
	public override double D(V3 p)
	{
		V3 ba = b - a; double l2 = ba.Dot(ba);
		double rr = ra - rb, a2 = l2 - rr * rr;
		if (l2 < 1e-12 || a2 <= 1e-9)
			return Math.Min((p - a).Len() - ra, (p - b).Len() - rb); // one end swallows the other
		double il2 = 1.0 / l2;
		V3 pa = p - a;
		double y = pa.Dot(ba), z = y - l2;
		V3 w = pa * l2 - ba * y;
		double x2 = w.Dot(w), y2 = y * y * l2, z2 = z * z * l2;
		double k = Math.Sign(rr) * rr * rr * x2;
		if (Math.Sign(z) * a2 * z2 > k) return Math.Sqrt(x2 + z2) * il2 - rb;
		if (Math.Sign(y) * a2 * y2 < k) return Math.Sqrt(x2 + y2) * il2 - ra;
		return (Math.Sqrt(x2 * a2 * il2) + y * rr) * il2 - ra;
	}
	public override void Bounds(ref V3 lo, ref V3 hi) { Grow(ref lo, ref hi, a, ra); Grow(ref lo, ref hi, b, rb); }
}

// Rounded box, optionally rotated.
public class RoundBox : Sdf
{
	V3 c, h; double round; Rot rot;
	public RoundBox(V3 c, V3 half, double round, Rot rot) { this.c = c; this.h = half; this.round = round; this.rot = rot; }
	public override double D(V3 p)
	{
		V3 q = rot.Inverse(p - c).Abs() - h + new V3(round, round, round);
		V3 m = new V3(Math.Max(q.X, 0), Math.Max(q.Y, 0), Math.Max(q.Z, 0));
		return m.Len() + Math.Min(Math.Max(q.X, Math.Max(q.Y, q.Z)), 0) - round;
	}
	public override void Bounds(ref V3 lo, ref V3 hi) { Grow(ref lo, ref hi, c, h.Len()); }
}

// A ring (torus) around an axis: Rot turns the default Y axis to where it should point.
public class Torus : Sdf
{
	V3 c; double major, minor; Rot rot;
	public Torus(V3 c, double major, double minor, Rot rot) { this.c = c; this.major = major; this.minor = minor; this.rot = rot; }
	public override double D(V3 p)
	{
		V3 q = rot.Inverse(p - c);
		double xz = Math.Sqrt(q.X * q.X + q.Z * q.Z) - major;
		return Math.Sqrt(xz * xz + q.Y * q.Y) - minor;
	}
	public override void Bounds(ref V3 lo, ref V3 hi) { Grow(ref lo, ref hi, c, major + minor); }
}

// A faceted crystal: a hexagonal prism of Radius along Axis from Base, Length long, tapering
// to a point over its last TipLength (distance is approximate, scaled to stay safe).
public class Crystal : Sdf
{
	V3 b, ax, u, w; double r, len, tip;
	public Crystal(V3 basePoint, V3 axis, double radius, double length, double tipLength, double twistDeg)
	{
		b = basePoint; ax = axis.Unit(); r = radius; len = length; tip = tipLength;
		V3 any = Math.Abs(ax.Y) < 0.9 ? new V3(0, 1, 0) : new V3(1, 0, 0);
		u = ax.Cross(any).Unit(); w = ax.Cross(u);
		double t = twistDeg * Math.PI / 180;
		V3 u2 = u * Math.Cos(t) + w * Math.Sin(t), w2 = ax.Cross(u2);
		u = u2; w = w2;
	}
	public override double D(V3 p)
	{
		V3 d = p - b;
		double y = d.Dot(ax), x = d.Dot(u), z = d.Dot(w);
		double width = r;
		if (y > len - tip) width = r * Math.Max(0, (len - y) / tip);
		double hex = 0;
		for (int i = 0; i < 3; i++)
		{
			double a = i * Math.PI / 3;
			hex = Math.Max(hex, Math.Abs(x * Math.Cos(a) + z * Math.Sin(a)));
		}
		return Math.Max(Math.Max(hex - width * 0.866, -y), y - len) * 0.7;
	}
	public override void Bounds(ref V3 lo, ref V3 hi) { Grow(ref lo, ref hi, b, r); Grow(ref lo, ref hi, b + ax * len, r); }
}

// A thin sheet (wing membranes, feathers): the region of the XY plane inside `inside` (a
// signed 2D distance, negative inside), Thickness thick, at depth Z0, cupped back by Bow
// (z grows with x squared, so the tip of a wing curls behind its root).
public class Sheet : Sdf
{
	Func<double, double, double> inside; double thick, bow, z0; double x0, y0, x1, y1;
	public Sheet(Func<double, double, double> inside2d, double thickness, double bow, double z0, double xLo, double yLo, double xHi, double yHi)
	{
		inside = inside2d; thick = thickness; this.bow = bow; this.z0 = z0; x0 = xLo; y0 = yLo; x1 = xHi; y1 = yHi;
	}
	public override double D(V3 p)
	{
		double z = p.Z - z0 - bow * p.X * p.X * 0.1;
		return Math.Max(inside(p.X, p.Y), Math.Abs(z) - thick / 2);
	}
	public override void Bounds(ref V3 l, ref V3 h)
	{
		double zl = z0 - thick, zh = z0 + thick + Math.Abs(bow) * Math.Max(x0 * x0, x1 * x1) * 0.1;
		if (bow < 0) { zl = z0 - thick - Math.Abs(bow) * Math.Max(x0 * x0, x1 * x1) * 0.1; zh = z0 + thick; }
		l = new V3(Math.Min(l.X, x0), Math.Min(l.Y, y0), Math.Min(l.Z, zl));
		h = new V3(Math.Max(h.X, x1), Math.Max(h.Y, y1), Math.Max(h.Z, zh));
	}
}

// 2D signed distances for Sheets.
public static class Flat
{
	// a polygon (x0, y0, x1, y1, ...), any winding
	public static Func<double, double, double> Poly(params double[] xy)
	{
		int n = xy.Length / 2;
		return (px, py) =>
		{
			double d = (px - xy[0]) * (px - xy[0]) + (py - xy[1]) * (py - xy[1]);
			double s = 1;
			for (int i = 0, j = n - 1; i < n; j = i, i++)
			{
				double ex = xy[j * 2] - xy[i * 2], ey = xy[j * 2 + 1] - xy[i * 2 + 1];
				double wx = px - xy[i * 2], wy = py - xy[i * 2 + 1];
				double t = Math.Max(0, Math.Min(1, (wx * ex + wy * ey) / (ex * ex + ey * ey)));
				double bx = wx - ex * t, by = wy - ey * t;
				d = Math.Min(d, bx * bx + by * by);
				bool c1 = py >= xy[i * 2 + 1], c2 = py < xy[j * 2 + 1], c3 = ex * wy > ey * wx;
				if ((c1 && c2 && c3) || (!c1 && !c2 && !c3)) s = -s;
			}
			return s * Math.Sqrt(d);
		};
	}
	public static Func<double, double, double> Circle(double cx, double cy, double r)
	{
		return (px, py) => Math.Sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy)) - r;
	}
	// a pointed leaf (a feather's vane): from (rootX, rootY) at angle deg, length len, widest w
	public static Func<double, double, double> Leaf(double rootX, double rootY, double deg, double len, double w)
	{
		double a = deg * Math.PI / 180, ca = Math.Cos(a), sa = Math.Sin(a);
		double half = len / 2, R = (half * half + w * w) / (2 * w);
		return (px, py) =>
		{
			double dx = px - rootX, dy = py - rootY;
			double u = dx * ca + dy * sa - half, v = -dx * sa + dy * ca;
			double d1 = Math.Sqrt(u * u + (v + (R - w)) * (v + (R - w))) - R;
			double d2 = Math.Sqrt(u * u + (v - (R - w)) * (v - (R - w))) - R;
			return Math.Max(d1, d2);
		};
	}
	public static Func<double, double, double> Union(params Func<double, double, double>[] fs)
	{
		return (x, y) => { double d = 1e9; foreach (var f in fs) d = Math.Min(d, f(x, y)); return d; };
	}
	public static Func<double, double, double> Minus(Func<double, double, double> a, params Func<double, double, double>[] cuts)
	{
		return (x, y) => { double d = a(x, y); foreach (var c in cuts) d = Math.Max(d, -c(x, y)); return d; };
	}
	// torn, uneven edges
	public static Func<double, double, double> Ragged(Func<double, double, double> a, double amp, double freq, int seed)
	{
		return (x, y) => a(x, y) + amp * Noise.Fbm(new V3(x * freq, y * freq, 0.5), seed);
	}
	// a bite out of the edge from (x1, y1) to (x2, y2), `depth` deep, away from the inside point (ix, iy)
	public static Func<double, double, double> Scallop(double x1, double y1, double x2, double y2, double depth, double ix, double iy)
	{
		double mx = (x1 + x2) / 2, my = (y1 + y2) / 2, cx = x2 - x1, cy = y2 - y1;
		double c = Math.Sqrt(cx * cx + cy * cy);
		double nx = -cy / c, ny = cx / c;
		if (nx * (mx - ix) + ny * (my - iy) < 0) { nx = -nx; ny = -ny; }
		double R = (c * c / 4 + depth * depth) / (2 * depth);
		return Circle(mx + nx * (R - depth), my + ny * (R - depth), R);
	}
	public static Func<double, double, double> Clip(Func<double, double, double> a, Func<double, double, double> b)
	{
		return (x, y) => Math.Max(a(x, y), b(x, y));
	}
}

// Grow (amount > 0) or shrink (amount < 0) a shape.
public class Offset : Sdf
{
	Sdf s; double amount;
	public Offset(Sdf s, double amount) { this.s = s; this.amount = amount; }
	public override double D(V3 p) { return s.D(p) - amount; }
	public override void Bounds(ref V3 lo, ref V3 hi)
	{
		V3 l = new V3(1e9, 1e9, 1e9), h = new V3(-1e9, -1e9, -1e9);
		s.Bounds(ref l, ref h);
		double g = Math.Max(0, amount);
		lo = new V3(Math.Min(lo.X, l.X - g), Math.Min(lo.Y, l.Y - g), Math.Min(lo.Z, l.Z - g));
		hi = new V3(Math.Max(hi.X, h.X + g), Math.Max(hi.Y, h.Y + g), Math.Max(hi.Z, h.Z + g));
	}
}

// Cracks: a network of thin wandering lines (where smooth noise crosses zero, about 1/freq
// apart), Width studs either side of the line, cut Depth deep into a shape's surface only.
// Shrink the same shape by less than Depth and colour it Neon, and the cracks glow (lava,
// haunted light); leave it out and they are just cracks.
public class Cracked : Sdf
{
	Sdf s; double freq, width, depth, k; int seed;
	public Cracked(Sdf s, double freq, double width, double depth, int seed, double k = 0.02) { this.s = s; this.freq = freq; this.width = width; this.depth = depth; this.seed = seed; this.k = k; }
	double N(V3 q) { return Noise.Value(q, seed) * 0.75 + Noise.Value(q * 2.03, seed + 1) * 0.25; }
	public override double D(V3 p)
	{
		double d = s.D(p);
		if (d > depth + 0.25 || d < -depth - 0.25) return d;
		// distance to the noise's zero line = its value over its slope (so every crack is
		// the same width, however fast the noise happens to change there)
		V3 q = p * freq;
		const double e = 0.04;
		double n = N(q);
		double gx = N(q + new V3(e, 0, 0)) - N(q - new V3(e, 0, 0));
		double gy = N(q + new V3(0, e, 0)) - N(q - new V3(0, e, 0));
		double gz = N(q + new V3(0, 0, e)) - N(q - new V3(0, 0, e));
		double slope = Math.Sqrt(gx * gx + gy * gy + gz * gz) / (2 * e) * freq;
		double crack = Math.Abs(n) / Math.Max(slope, 0.35 * freq) - width;
		double cut = Math.Max(crack, -(d + depth));
		return -Union.Smin(-d, cut, k);
	}
	public override void Bounds(ref V3 lo, ref V3 hi) { s.Bounds(ref lo, ref hi); }
}

// Translate a shape (reuse one sculpt in several places).
public class Move : Sdf
{
	Sdf s; V3 by; Rot rot;
	public Move(Sdf s, V3 by, Rot rot) { this.s = s; this.by = by; this.rot = rot; }
	public Move(Sdf s, V3 by) : this(s, by, Rot.Deg(0, 0, 0)) { }
	public override double D(V3 p) { return s.D(rot.Inverse(p - by)); }
	public override void Bounds(ref V3 lo, ref V3 hi)
	{
		V3 l = new V3(1e9, 1e9, 1e9), h = new V3(-1e9, -1e9, -1e9);
		s.Bounds(ref l, ref h);
		for (int i = 0; i < 8; i++)
		{
			V3 c = new V3((i & 1) == 0 ? l.X : h.X, (i & 2) == 0 ? l.Y : h.Y, (i & 4) == 0 ? l.Z : h.Z);
			V3 w = rot.Apply(c) + by;
			lo = new V3(Math.Min(lo.X, w.X), Math.Min(lo.Y, w.Y), Math.Min(lo.Z, w.Z));
			hi = new V3(Math.Max(hi.X, w.X), Math.Max(hi.Y, w.Y), Math.Max(hi.Z, w.Z));
		}
	}
}

public class Union : Sdf
{
	List<Sdf> parts = new List<Sdf>(); double k;
	List<V3> boxLo = new List<V3>(), boxHi = new List<V3>();
	public Union(double k, params Sdf[] items) { this.k = k; foreach (var s in items) Add(s); }
	public Union Add(Sdf s)
	{
		parts.Add(s);
		V3 l = new V3(1e9, 1e9, 1e9), h = new V3(-1e9, -1e9, -1e9);
		s.Bounds(ref l, ref h);
		boxLo.Add(l); boxHi.Add(h);
		return this;
	}
	public static double Smin(double a, double b, double k)
	{
		if (k <= 0) return Math.Min(a, b);
		double h = Math.Max(k - Math.Abs(a - b), 0) / k;
		return Math.Min(a, b) - h * h * k * 0.25;
	}
	public override double D(V3 p)
	{
		// a piece whose box is farther than the current distance (plus the blend and a margin
		// for rough surfaces) can't change the result: skip it
		double d = 1e9;
		for (int i = 0; i < parts.Count; i++)
		{
			V3 l = boxLo[i], h = boxHi[i];
			double qx = Math.Max(Math.Max(l.X - p.X, p.X - h.X), 0), qy = Math.Max(Math.Max(l.Y - p.Y, p.Y - h.Y), 0), qz = Math.Max(Math.Max(l.Z - p.Z, p.Z - h.Z), 0);
			if (d < 1e8 && Math.Sqrt(qx * qx + qy * qy + qz * qz) > d + k + 0.2) continue;
			d = Smin(d, parts[i].D(p), k);
		}
		return d;
	}
	public override void Bounds(ref V3 lo, ref V3 hi) { foreach (var s in parts) s.Bounds(ref lo, ref hi); }
}

// a minus b (smoothly carved)
public class Subtract : Sdf
{
	Sdf a, b; double k;
	public Subtract(Sdf a, Sdf b, double k) { this.a = a; this.b = b; this.k = k; }
	public override double D(V3 p) { return -Union.Smin(-a.D(p), b.D(p), k); }
	public override void Bounds(ref V3 lo, ref V3 hi) { a.Bounds(ref lo, ref hi); }
}

public class Intersect : Sdf
{
	Sdf a, b; double k;
	public Intersect(Sdf a, Sdf b, double k) { this.a = a; this.b = b; this.k = k; }
	public override double D(V3 p) { return -Union.Smin(-a.D(p), -b.D(p), k); }
	public override void Bounds(ref V3 lo, ref V3 hi) { a.Bounds(ref lo, ref hi); }
}

// Mirror across X = 0: author the right side, get both.
public class MirrorX : Sdf
{
	Sdf s;
	public MirrorX(Sdf s) { this.s = s; }
	public override double D(V3 p) { return s.D(new V3(Math.Abs(p.X), p.Y, p.Z)); }
	public override void Bounds(ref V3 lo, ref V3 hi)
	{
		V3 l = new V3(1e9, 1e9, 1e9), h = new V3(-1e9, -1e9, -1e9);
		s.Bounds(ref l, ref h);
		double x = Math.Max(Math.Abs(l.X), Math.Abs(h.X));
		lo = new V3(Math.Min(lo.X, -x), Math.Min(lo.Y, l.Y), Math.Min(lo.Z, l.Z));
		hi = new V3(Math.Max(hi.X, x), Math.Max(hi.Y, h.Y), Math.Max(hi.Z, h.Z));
	}
}

// Organic surface: bumps and creases (fbm value noise) pushed in and out of the surface.
public class Rough : Sdf
{
	Sdf s; double amp, freq; int seed;
	public Rough(Sdf s, double amp, double freq, int seed) { this.s = s; this.amp = amp; this.freq = freq; this.seed = seed; }
	public override double D(V3 p) { return s.D(p) + amp * Noise.Fbm(p * freq, seed); }
	public override void Bounds(ref V3 lo, ref V3 hi) { s.Bounds(ref lo, ref hi); }
}

public static class Noise
{
	static double Hash(int x, int y, int z, int seed)
	{
		unchecked
		{
			int h = x * 374761393 + y * 668265263 + z * 2147483647 + seed * 144665;
			h = (h ^ (h >> 13)) * 1274126177;
			h ^= h >> 16;
			return (h & 0xffffff) / (double)0xffffff * 2 - 1;
		}
	}
	static double Smooth(double t) { return t * t * (3 - 2 * t); }
	public static double Value(V3 p, int seed)
	{
		int x = (int)Math.Floor(p.X), y = (int)Math.Floor(p.Y), z = (int)Math.Floor(p.Z);
		double fx = Smooth(p.X - x), fy = Smooth(p.Y - y), fz = Smooth(p.Z - z);
		double r = 0;
		for (int i = 0; i < 8; i++)
		{
			int dx = i & 1, dy = (i >> 1) & 1, dz = (i >> 2) & 1;
			double w = (dx == 1 ? fx : 1 - fx) * (dy == 1 ? fy : 1 - fy) * (dz == 1 ? fz : 1 - fz);
			r += w * Hash(x + dx, y + dy, z + dz, seed);
		}
		return r;
	}
	public static double Fbm(V3 p, int seed)
	{
		return Value(p, seed) * 0.6 + Value(p * 2.03, seed + 1) * 0.28 + Value(p * 4.1, seed + 2) * 0.12;
	}
}

// Shapes made of many pieces.
public static class Shapes
{
	// A horn / spike / tentacle: a tapered tube along a quadratic Bezier (a -> control -> b).
	public static Sdf Horn(V3 a, V3 control, V3 b, double rBase, double rTip, int segments = 10)
	{
		var u = new Union(0.0);
		V3 prev = a; double prevR = rBase;
		for (int i = 1; i <= segments; i++)
		{
			double t = (double)i / segments;
			V3 p = (1 - t) * (1 - t) * a + 2 * (1 - t) * t * control + t * t * b;
			double r = rBase + (rTip - rBase) * Math.Pow(t, 0.85);
			u.Add(new RoundCone(prev, p, prevR, r));
			prev = p; prevR = r;
		}
		return u;
	}
	// A row of cone teeth between two points, pointing along `dir` (tip: the point's radius as
	// a share of the root's - small = fangs, large = blunt human teeth).
	public static Sdf Teeth(V3 from, V3 to, int count, V3 dir, double length, double width, double tip = 0.12)
	{
		var u = new Union(0.0);
		for (int i = 0; i < count; i++)
		{
			double t = count == 1 ? 0.5 : (double)i / (count - 1);
			V3 root = V3.Lerp(from, to, t);
			double l = length * (0.75 + 0.5 * Math.Abs(Math.Sin(i * 2.3)));
			u.Add(new RoundCone(root, root + dir.Unit() * l, width, width * tip));
		}
		return u;
	}
	// A smooth tube through several points (Catmull-Rom), its radius tapering from rBase to
	// rTip; ribs > 0 rings it like a ram's horn or a segmented tail.
	public static List<V3> Spline(V3[] pts, int perSpan)
	{
		var samples = new List<V3>();
		for (int i = 0; i < pts.Length - 1; i++)
		{
			V3 p0 = pts[Math.Max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[Math.Min(pts.Length - 1, i + 2)];
			for (int s = 0; s < perSpan; s++)
			{
				double t = (double)s / perSpan, t2 = t * t, t3 = t2 * t;
				samples.Add(0.5 * ((2 * p1) + (-1 * p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-1 * p0 + 3 * p1 - 3 * p2 + p3) * t3));
			}
		}
		samples.Add(pts[pts.Length - 1]);
		return samples;
	}
	public static Sdf Path(V3[] pts, double rBase, double rTip, int perSpan = 6, double ribs = 0, double ribDepth = 0.08)
	{
		var samples = Spline(pts, perSpan);
		var u = new Union(0.0);
		int n = samples.Count;
		for (int i = 0; i < n - 1; i++)
		{
			double ta = (double)i / (n - 1), tb = (double)(i + 1) / (n - 1);
			double ra = rBase + (rTip - rBase) * Math.Pow(ta, 0.9), rb = rBase + (rTip - rBase) * Math.Pow(tb, 0.9);
			if (ribs > 0) { ra *= 1 + ribDepth * Math.Sin(ta * ribs * Math.PI * 2); rb *= 1 + ribDepth * Math.Sin(tb * ribs * Math.PI * 2); }
			u.Add(new RoundCone(samples[i], samples[i + 1], ra, rb));
		}
		return u;
	}
}

// A named mesh of a part: its SDF, its look, and (optionally) the joint group it rides on.
public class MeshData
{
	public List<V3> V = new List<V3>(), N = new List<V3>();
	public List<int> T = new List<int>();
	public V3 Lo, Hi;
}

public static class Mesher
{
	public static V3 Gradient(Sdf s, V3 p)
	{
		const double e = 0.004;
		return new V3(s.D(p + new V3(e, 0, 0)) - s.D(p - new V3(e, 0, 0)), s.D(p + new V3(0, e, 0)) - s.D(p - new V3(0, e, 0)), s.D(p + new V3(0, 0, e)) - s.D(p - new V3(0, 0, e))).Unit();
	}

	// Naive Surface Nets: one vertex per cell the surface passes through (the mean of its edge
	// crossings, pulled onto the surface), one quad per grid edge that crosses it.
	public static MeshData Build(Sdf s, double h)
	{
		V3 lo = new V3(1e9, 1e9, 1e9), hi = new V3(-1e9, -1e9, -1e9);
		s.Bounds(ref lo, ref hi);
		lo = lo - new V3(2 * h, 2 * h, 2 * h); hi = hi + new V3(2 * h, 2 * h, 2 * h);
		int nx = (int)Math.Ceiling((hi.X - lo.X) / h) + 1, ny = (int)Math.Ceiling((hi.Y - lo.Y) / h) + 1, nz = (int)Math.Ceiling((hi.Z - lo.Z) / h) + 1;
		var f = new double[nx * ny * nz];
		Func<int, int, int, int> I = (x, y, z) => (z * ny + y) * nx + x;
		System.Threading.Tasks.Parallel.For(0, nz, z =>
		{
			for (int y = 0; y < ny; y++)
				for (int x = 0; x < nx; x++)
					f[I(x, y, z)] = s.D(lo + new V3(x * h, y * h, z * h));
		});
		var cellVert = new Dictionary<int, int>();
		var mesh = new MeshData();
		int[,] corners = { { 0, 0, 0 }, { 1, 0, 0 }, { 0, 1, 0 }, { 1, 1, 0 }, { 0, 0, 1 }, { 1, 0, 1 }, { 0, 1, 1 }, { 1, 1, 1 } };
		int[,] edges = { { 0, 1 }, { 2, 3 }, { 4, 5 }, { 6, 7 }, { 0, 2 }, { 1, 3 }, { 4, 6 }, { 5, 7 }, { 0, 4 }, { 1, 5 }, { 2, 6 }, { 3, 7 } };
		for (int z = 0; z < nz - 1; z++)
			for (int y = 0; y < ny - 1; y++)
				for (int x = 0; x < nx - 1; x++)
				{
					var vals = new double[8];
					int mask = 0;
					for (int c = 0; c < 8; c++)
					{
						vals[c] = f[I(x + corners[c, 0], y + corners[c, 1], z + corners[c, 2])];
						if (vals[c] < 0) mask |= 1 << c;
					}
					if (mask == 0 || mask == 255) continue;
					V3 sum = new V3(0, 0, 0); int n = 0;
					for (int e = 0; e < 12; e++)
					{
						int a = edges[e, 0], b = edges[e, 1];
						if ((vals[a] < 0) == (vals[b] < 0)) continue;
						double t = vals[a] / (vals[a] - vals[b]);
						V3 pa = new V3(x + corners[a, 0], y + corners[a, 1], z + corners[a, 2]);
						V3 pb = new V3(x + corners[b, 0], y + corners[b, 1], z + corners[b, 2]);
						sum = sum + V3.Lerp(pa, pb, t); n++;
					}
					V3 p = lo + (sum * (1.0 / n)) * h;
					// pull onto the surface
					for (int it = 0; it < 2; it++)
					{
						double d = s.D(p);
						p = p - Gradient(s, p) * d;
					}
					cellVert[I(x, y, z)] = mesh.V.Count;
					mesh.V.Add(p);
					mesh.N.Add(Gradient(s, p));
				}
		// quads across every sign-changing grid edge
		for (int z = 1; z < nz - 1; z++)
			for (int y = 1; y < ny - 1; y++)
				for (int x = 1; x < nx - 1; x++)
				{
					bool inside = f[I(x, y, z)] < 0;
					// edge along +X: cells sharing it are (x, y-1..y, z-1..z)
					if (x < nx - 1 && inside != (f[I(x + 1, y, z)] < 0))
						Quad(mesh, cellVert, I(x, y - 1, z - 1), I(x, y, z - 1), I(x, y, z), I(x, y - 1, z), inside);
					if (y < ny - 1 && inside != (f[I(x, y + 1, z)] < 0))
						Quad(mesh, cellVert, I(x - 1, y, z - 1), I(x - 1, y, z), I(x, y, z), I(x, y, z - 1), inside);
					if (z < nz - 1 && inside != (f[I(x, y, z + 1)] < 0))
						Quad(mesh, cellVert, I(x - 1, y - 1, z), I(x, y - 1, z), I(x, y, z), I(x - 1, y, z), inside);
				}
		Finish(mesh, s, false);
		return mesh;
	}

	// Normals from the SDF (and, after simplifying, every vertex pulled back onto the true
	// surface), every triangle wound to face out, bounds.
	public static void Finish(MeshData mesh, Sdf s, bool reproject)
	{
		if (reproject)
			for (int i = 0; i < mesh.V.Count; i++)
			{
				V3 p = mesh.V[i];
				p = p - Gradient(s, p) * s.D(p);
				mesh.V[i] = p;
				mesh.N[i] = Gradient(s, p);
			}
		// wind every triangle so it faces out (its normal agrees with the surface's)
		for (int t = 0; t < mesh.T.Count; t += 3)
		{
			V3 a = mesh.V[mesh.T[t]], b = mesh.V[mesh.T[t + 1]], c = mesh.V[mesh.T[t + 2]];
			V3 n = (b - a).Cross(c - a);
			V3 avg = mesh.N[mesh.T[t]] + mesh.N[mesh.T[t + 1]] + mesh.N[mesh.T[t + 2]];
			if (n.Dot(avg) < 0) { int s2 = mesh.T[t + 1]; mesh.T[t + 1] = mesh.T[t + 2]; mesh.T[t + 2] = s2; }
		}
		mesh.Lo = new V3(1e9, 1e9, 1e9); mesh.Hi = new V3(-1e9, -1e9, -1e9);
		foreach (var v in mesh.V)
		{
			mesh.Lo = new V3(Math.Min(mesh.Lo.X, v.X), Math.Min(mesh.Lo.Y, v.Y), Math.Min(mesh.Lo.Z, v.Z));
			mesh.Hi = new V3(Math.Max(mesh.Hi.X, v.X), Math.Max(mesh.Hi.Y, v.Y), Math.Max(mesh.Hi.Z, v.Z));
		}
	}

	static void Quad(MeshData m, Dictionary<int, int> cv, int a, int b, int c, int d, bool flip)
	{
		int va, vb, vc, vd;
		if (!cv.TryGetValue(a, out va) || !cv.TryGetValue(b, out vb) || !cv.TryGetValue(c, out vc) || !cv.TryGetValue(d, out vd)) return;
		if (flip) { int t = vb; vb = vd; vd = t; }
		// split along the shorter diagonal
		if ((m.V[va] - m.V[vc]).Len() < (m.V[vb] - m.V[vd]).Len())
		{
			m.T.AddRange(new[] { va, vb, vc, va, vc, vd });
		}
		else
		{
			m.T.AddRange(new[] { va, vb, vd, vb, vc, vd });
		}
	}
}

