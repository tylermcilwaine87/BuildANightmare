// A tiny software renderer: each part from four angles side by side in one PNG, smooth
// shaded (sky / ground light, a key light, a rim light), neon glowing. For judging a sculpt
// without Studio. Uses System.Drawing only to save the PNG.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;

public static class Render
{
	public class Item { public MeshData Mesh; public int[] Color; public string Material; }

	public static void Sheet(string path, List<Item> items, int cell = 420)
	{
		double[][] views = { new double[] { 0, 8 }, new double[] { 35, 14 }, new double[] { 90, 6 }, new double[] { 160, 18 } };
		int w = cell * views.Length, h = cell;
		var color = new int[w * h];
		var depth = new double[w * h];
		for (int i = 0; i < color.Length; i++) { color[i] = Pack(27, 30, 38); depth[i] = double.MaxValue; }
		V3 lo = new V3(1e9, 1e9, 1e9), hi = new V3(-1e9, -1e9, -1e9);
		foreach (var it in items)
		{
			lo = new V3(Math.Min(lo.X, it.Mesh.Lo.X), Math.Min(lo.Y, it.Mesh.Lo.Y), Math.Min(lo.Z, it.Mesh.Lo.Z));
			hi = new V3(Math.Max(hi.X, it.Mesh.Hi.X), Math.Max(hi.Y, it.Mesh.Hi.Y), Math.Max(hi.Z, it.Mesh.Hi.Z));
		}
		V3 center = (lo + hi) * 0.5;
		double radius = (hi - lo).Len() * 0.5;
		for (int vi = 0; vi < views.Length; vi++)
		{
			double yaw = views[vi][0] * Math.PI / 180, pitch = views[vi][1] * Math.PI / 180;
			// yaw 0 looks at the front (the part faces -Z)
			V3 eye = center + new V3(Math.Sin(yaw) * Math.Cos(pitch), Math.Sin(pitch), -Math.Cos(yaw) * Math.Cos(pitch)) * (radius * 3.2);
			V3 fwd = (center - eye).Unit();
			V3 right = fwd.Cross(new V3(0, 1, 0)).Unit();
			V3 up = right.Cross(fwd);
			double focal = cell * 0.92 / (radius * 2.2) * (radius * 3.2);
			int ox = vi * cell;
			foreach (var it in items)
			{
				var m = it.Mesh;
				int n = m.V.Count;
				var sx = new double[n]; var sy = new double[n]; var sz = new double[n];
				for (int i = 0; i < n; i++)
				{
					V3 d = m.V[i] - eye;
					double z = d.Dot(fwd);
					sx[i] = ox + cell / 2.0 + d.Dot(right) / z * focal;
					sy[i] = cell / 2.0 - d.Dot(up) / z * focal;
					sz[i] = z;
				}
				for (int t = 0; t < m.T.Count; t += 3)
				{
					int a = m.T[t], b = m.T[t + 1], c = m.T[t + 2];
					Raster(color, depth, w, h, ox, ox + cell, sx, sy, sz, a, b, c, m, it, eye);
				}
			}
		}
		using (var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb))
		{
			var data = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
			System.Runtime.InteropServices.Marshal.Copy(color, 0, data.Scan0, color.Length);
			bmp.UnlockBits(data);
			bmp.Save(path, ImageFormat.Png);
		}
	}

	static int Pack(double r, double g, double b)
	{
		int R = (int)Math.Max(0, Math.Min(255, r)), G = (int)Math.Max(0, Math.Min(255, g)), B = (int)Math.Max(0, Math.Min(255, b));
		return unchecked((int)0xff000000) | (R << 16) | (G << 8) | B;
	}

	static void Raster(int[] color, double[] depth, int w, int h, int minX, int maxX, double[] sx, double[] sy, double[] sz, int a, int b, int c, MeshData m, Item it, V3 eye)
	{
		double x0 = sx[a], y0 = sy[a], x1 = sx[b], y1 = sy[b], x2 = sx[c], y2 = sy[c];
		double area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0);
		if (Math.Abs(area) < 1e-9) return;
		int bx0 = Math.Max(minX, (int)Math.Floor(Math.Min(x0, Math.Min(x1, x2)))), bx1 = Math.Min(maxX - 1, (int)Math.Ceiling(Math.Max(x0, Math.Max(x1, x2))));
		int by0 = Math.Max(0, (int)Math.Floor(Math.Min(y0, Math.Min(y1, y2)))), by1 = Math.Min(h - 1, (int)Math.Ceiling(Math.Max(y0, Math.Max(y1, y2))));
		V3 key = new V3(0.45, 0.8, -0.4).Unit(), rim = new V3(-0.6, 0.3, 0.75).Unit();
		bool neon = it.Material == "Neon";
		bool metal = it.Material == "Metal";
		for (int y = by0; y <= by1; y++)
			for (int x = bx0; x <= bx1; x++)
			{
				double px = x + 0.5, py = y + 0.5;
				double w0 = ((x1 - px) * (y2 - py) - (x2 - px) * (y1 - py)) / area;
				double w1 = ((x2 - px) * (y0 - py) - (x0 - px) * (y2 - py)) / area;
				double w2 = 1 - w0 - w1;
				if (w0 < 0 || w1 < 0 || w2 < 0) continue;
				double z = w0 * sz[a] + w1 * sz[b] + w2 * sz[c];
				int idx = y * w + x;
				if (z >= depth[idx]) continue;
				depth[idx] = z;
				V3 n = (m.N[a] * w0 + m.N[b] * w1 + m.N[c] * w2).Unit();
				V3 pos = m.V[a] * w0 + m.V[b] * w1 + m.V[c] * w2;
				V3 view = (eye - pos).Unit();
				if (n.Dot(view) < 0) n = -n; // (back faces: show them lit, the importer decides)
				double r = it.Color[0], g = it.Color[1], bl = it.Color[2];
				if (neon)
				{
					color[idx] = Pack(r * 1.1 + 40, g * 1.1 + 30, bl * 1.1 + 30);
					continue;
				}
				double sky = 0.42 + 0.33 * n.Y;
				double diff = Math.Max(0, n.Dot(key)) * 0.85;
				double back = Math.Pow(Math.Max(0, n.Dot(rim)), 2) * 0.35;
				V3 half = (key + view).Unit();
				double spec = Math.Pow(Math.Max(0, n.Dot(half)), metal ? 30 : 14) * (metal ? 0.55 : 0.18);
				double lit = sky + diff + back;
				color[idx] = Pack(r * lit + 255 * spec, g * lit + 255 * spec, bl * lit + 255 * spec);
			}
	}
}
