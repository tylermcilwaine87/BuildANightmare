// Quadric-error mesh simplification (Garland & Heckbert): repeatedly collapse the edge whose
// removal changes the shape least, never folding a face over, until the triangle budget is
// met. The sculpt keeps its silhouette and creases with a fraction of the triangles.
using System;
using System.Collections.Generic;

public static class Simplify
{
	struct Quadric
	{
		public double a, b, c, d, e, f, g, h, i, j; // symmetric 4x4: [a b c d; b e f g; c f h i; d g i j]
		public static Quadric Plane(double nx, double ny, double nz, double dd)
		{
			return new Quadric { a = nx * nx, b = nx * ny, c = nx * nz, d = nx * dd, e = ny * ny, f = ny * nz, g = ny * dd, h = nz * nz, i = nz * dd, j = dd * dd };
		}
		public static Quadric operator +(Quadric p, Quadric q)
		{
			return new Quadric { a = p.a + q.a, b = p.b + q.b, c = p.c + q.c, d = p.d + q.d, e = p.e + q.e, f = p.f + q.f, g = p.g + q.g, h = p.h + q.h, i = p.i + q.i, j = p.j + q.j };
		}
		public double Error(V3 v)
		{
			double x = v.X, y = v.Y, z = v.Z;
			return a * x * x + 2 * b * x * y + 2 * c * x * z + 2 * d * x + e * y * y + 2 * f * y * z + 2 * g * y + h * z * z + 2 * i * z + j;
		}
	}

	class Candidate : IComparable<Candidate>
	{
		public double Cost; public int A, B, Stamp; public V3 Target; public long Id;
		public int CompareTo(Candidate o) { int c = Cost.CompareTo(o.Cost); return c != 0 ? c : Id.CompareTo(o.Id); }
	}

	public static MeshData Run(MeshData mesh, int targetTris)
	{
		int nv = mesh.V.Count, nt = mesh.T.Count / 3;
		if (nt <= targetTris) return mesh;
		var pos = new List<V3>(mesh.V);
		var tri = new int[nt * 3];
		mesh.T.CopyTo(tri);
		var alive = new bool[nt];
		var q = new Quadric[nv];
		var vertFaces = new List<int>[nv];
		var removed = new bool[nv];
		var stamp = new int[nv];
		for (int v = 0; v < nv; v++) vertFaces[v] = new List<int>();
		for (int t = 0; t < nt; t++)
		{
			alive[t] = true;
			V3 a = pos[tri[t * 3]], b = pos[tri[t * 3 + 1]], c = pos[tri[t * 3 + 2]];
			V3 n = (b - a).Cross(c - a);
			double area = n.Len();
			if (area < 1e-12) continue;
			n = n * (1 / area);
			var plane = Quadric.Plane(n.X, n.Y, n.Z, -n.Dot(a));
			for (int k = 0; k < 3; k++) { q[tri[t * 3 + k]] = q[tri[t * 3 + k]] + plane; vertFaces[tri[t * 3 + k]].Add(t); }
		}
		var heap = new SortedSet<Candidate>();
		long ids = 0;
		Action<int, int> push = (va, vb) =>
		{
			var qq = q[va] + q[vb];
			V3 mid = (pos[va] + pos[vb]) * 0.5;
			V3 best = mid; double cost = qq.Error(mid);
			double ca = qq.Error(pos[va]), cb = qq.Error(pos[vb]);
			if (ca < cost) { cost = ca; best = pos[va]; }
			if (cb < cost) { cost = cb; best = pos[vb]; }
			heap.Add(new Candidate { Cost = cost, A = va, B = vb, Stamp = stamp[va] + stamp[vb] * 7919, Target = best, Id = ids++ });
		};
		var seen = new HashSet<long>();
		for (int t = 0; t < nt; t++)
			for (int k = 0; k < 3; k++)
			{
				int va = tri[t * 3 + k], vb = tri[t * 3 + (k + 1) % 3];
				long key = Math.Min(va, vb) * (long)nv + Math.Max(va, vb);
				if (seen.Add(key)) push(Math.Min(va, vb), Math.Max(va, vb));
			}
		int liveTris = nt;
		while (liveTris > targetTris && heap.Count > 0)
		{
			var cand = heap.Min;
			heap.Remove(cand);
			int a = cand.A, b = cand.B;
			if (removed[a] || removed[b] || cand.Stamp != stamp[a] + stamp[b] * 7919) continue;
			// would any face around a or b flip (or collapse to a sliver)?
			bool bad = false;
			foreach (int v in new[] { a, b })
			{
				foreach (int t in vertFaces[v])
				{
					if (!alive[t]) continue;
					int i0 = tri[t * 3], i1 = tri[t * 3 + 1], i2 = tri[t * 3 + 2];
					bool hasA = i0 == a || i1 == a || i2 == a, hasB = i0 == b || i1 == b || i2 == b;
					if (hasA && hasB) continue; // this face disappears
					V3 p0 = pos[i0], p1 = pos[i1], p2 = pos[i2];
					V3 before = (p1 - p0).Cross(p2 - p0);
					if (i0 == v) p0 = cand.Target; if (i1 == v) p1 = cand.Target; if (i2 == v) p2 = cand.Target;
					V3 after = (p1 - p0).Cross(p2 - p0);
					if (after.Len() < 1e-12 || before.Unit().Dot(after.Unit()) < 0.3) { bad = true; break; }
				}
				if (bad) break;
			}
			if (bad) continue;
			// collapse b into a
			pos[a] = cand.Target;
			q[a] = q[a] + q[b];
			removed[b] = true;
			foreach (int t in vertFaces[b])
			{
				if (!alive[t]) continue;
				bool hasA = tri[t * 3] == a || tri[t * 3 + 1] == a || tri[t * 3 + 2] == a;
				if (hasA) { alive[t] = false; liveTris--; continue; }
				for (int k = 0; k < 3; k++) if (tri[t * 3 + k] == b) tri[t * 3 + k] = a;
				vertFaces[a].Add(t);
			}
			stamp[a]++;
			// re-cost the edges around a
			var neighbours = new HashSet<int>();
			foreach (int t in vertFaces[a])
			{
				if (!alive[t]) continue;
				for (int k = 0; k < 3; k++) if (tri[t * 3 + k] != a) neighbours.Add(tri[t * 3 + k]);
			}
			foreach (int nb in neighbours) { stamp[nb]++; }
			foreach (int nb in neighbours)
			{
				// every edge touching a neighbour changed stamp: re-push them all
				foreach (int t in vertFaces[nb])
				{
					if (!alive[t]) continue;
					for (int k = 0; k < 3; k++)
					{
						int o = tri[t * 3 + k];
						if (o != nb && !removed[o]) push(Math.Min(nb, o), Math.Max(nb, o));
					}
				}
			}
		}
		// compact
		var map = new int[nv];
		var outMesh = new MeshData();
		for (int v = 0; v < nv; v++) map[v] = -1;
		for (int t = 0; t < nt; t++)
		{
			if (!alive[t]) continue;
			int i0 = tri[t * 3], i1 = tri[t * 3 + 1], i2 = tri[t * 3 + 2];
			if (i0 == i1 || i1 == i2 || i0 == i2) continue;
			foreach (int v in new[] { i0, i1, i2 })
				if (map[v] < 0) { map[v] = outMesh.V.Count; outMesh.V.Add(pos[v]); outMesh.N.Add(mesh.N[v]); }
			outMesh.T.Add(map[i0]); outMesh.T.Add(map[i1]); outMesh.T.Add(map[i2]);
		}
		return outMesh;
	}
}
