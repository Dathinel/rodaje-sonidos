# Sintetiza los efectos de sonido de rodaje-sonidos en <Destino>\sonidos\<categoría>\<id>.wav: osciladores, ruido con un
# generador propio de semilla fija, filtros biquad, barridos, FM y una reverberación sencilla. No usa muestras de nadie y da
# los mismos bytes en cada corrida. Lo llama empaquetar.ps1. Con -Manifiesto <ruta> escribe además el paquete.json.
# Las fórmulas van en C# porque en PowerShell tardarían minutos.
param(
    [Parameter(Mandatory = $true)][string]$Destino,
    [string]$Manifiesto = ''
)

$ErrorActionPreference = 'Stop'

if (-not ('RodajeSonidos.Lib' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;

namespace RodajeSonidos
{
    public sealed class Def
    {
        public readonly string Id, Cat, Name;
        public readonly double Dur, Db;
        public readonly int Ch;
        public readonly bool Loop;

        public Def(string id, string cat, string name, double dur, int ch, double db, bool loop)
        {
            Id = id; Cat = cat; Name = name; Dur = dur; Ch = ch; Db = db; Loop = loop;
        }
    }

    // xorshift64 sembrado con el FNV-1a del nombre: el mismo ruido en cualquier equipo.
    public sealed class Rng
    {
        private ulong s;

        public Rng(string key)
        {
            ulong h = 1469598103934665603UL;
            foreach (char c in key) { h ^= c; h *= 1099511628211UL; }
            s = h == 0 ? 1 : h;
        }

        public double Next()
        {
            s ^= s << 13; s ^= s >> 7; s ^= s << 17;
            return (s >> 11) * (1.0 / 9007199254740992.0);
        }

        public double White() { return Next() * 2 - 1; }
    }

    public sealed class Pink
    {
        private double b0, b1, b2;

        public double Next(Rng r)
        {
            double w = r.White();
            b0 = 0.99765 * b0 + w * 0.0990460;
            b1 = 0.96300 * b1 + w * 0.2965164;
            b2 = 0.57000 * b2 + w * 1.0526913;
            return (b0 + b1 + b2 + w * 0.1848) * 0.2;
        }
    }

    public sealed class Brown
    {
        private double b;

        public double Next(Rng r) { b = b * 0.998 + r.White() * 0.04; return b; }
    }

    // Biquad en forma directa II transpuesta. 0 = pasa bajos, 1 = pasa altos, 2 = pasa banda (0 dB en el centro).
    public sealed class Bq
    {
        private double b0, b1, b2, a1, a2, z1, z2;

        public void Set(int type, double f, double q)
        {
            double w = 2 * Math.PI * Math.Max(10, Math.Min(f, 22000)) / Snd.Fs, cs = Math.Cos(w), al = Math.Sin(w) / (2 * q), a0 = 1 + al;
            double n0, n1, n2;
            if (type == 0) { n0 = (1 - cs) / 2; n1 = 1 - cs; n2 = n0; }
            else if (type == 1) { n0 = (1 + cs) / 2; n1 = -(1 + cs); n2 = n0; }
            else { n0 = al; n1 = 0; n2 = -al; }
            b0 = n0 / a0; b1 = n1 / a0; b2 = n2 / a0; a1 = -2 * cs / a0; a2 = (1 - al) / a0;
        }

        public static Bq Of(int type, double f, double q) { var b = new Bq(); b.Set(type, f, q); return b; }

        public double P(double x)
        {
            double y = b0 * x + z1;
            z1 = b1 * x - a1 * y + z2;
            z2 = b2 * x - a2 * y;
            return y;
        }
    }

    public sealed class Snd
    {
        public const int Fs = 48000;
        public readonly double[] L, R;
        public readonly int N;

        public Snd(int n, int ch) { N = n; L = new double[n]; R = ch == 2 ? new double[n] : null; }

        // Panorama de potencia constante, de -1 (izquierda) a 1 (derecha).
        public void Add(int i, double v, double pan)
        {
            if (i < 0 || i >= N) return;
            if (R == null) { L[i] += v; return; }
            double a = (Math.Max(-1, Math.Min(1, pan)) + 1) * Math.PI / 4;
            L[i] += v * Math.Cos(a); R[i] += v * Math.Sin(a);
        }
    }

    public static class Lib
    {
        const int Fs = Snd.Fs;
        const double Tau = 2 * Math.PI;
        const double Crossfade = 0.5;

        public static readonly Def[] All =
        {
            new Def("golpe-bombo", "golpes", "Bombo", 0.5, 1, -3, false),
            new Def("golpe-seco", "golpes", "Golpe seco", 0.25, 1, -3, false),
            new Def("golpe-grave", "golpes", "Golpe grave", 1.0, 1, -3, false),
            new Def("golpe-madera", "golpes", "Golpe de madera", 0.3, 1, -3, false),
            new Def("palmada", "golpes", "Palmada", 0.4, 1, -3, false),
            new Def("golpe-caja", "golpes", "Caja", 0.4, 1, -3, false),

            new Def("swoosh-corto", "swooshes", "Swoosh corto", 0.4, 2, -3, false),
            new Def("swoosh-medio", "swooshes", "Swoosh medio", 0.7, 2, -3, false),
            new Def("swoosh-largo", "swooshes", "Swoosh largo", 1.2, 2, -3, false),
            new Def("swoosh-izquierda-derecha", "swooshes", "Swoosh de izquierda a derecha", 0.8, 2, -3, false),
            new Def("swoosh-derecha-izquierda", "swooshes", "Swoosh de derecha a izquierda", 0.8, 2, -3, false),
            new Def("whoosh-grave", "swooshes", "Whoosh grave", 1.0, 2, -3, false),
            new Def("whoosh-aire", "swooshes", "Whoosh de aire", 1.5, 2, -3, false),
            new Def("swoosh-doble", "swooshes", "Swoosh doble", 0.9, 2, -3, false),

            new Def("clic", "clics", "Clic", 0.06, 1, -6, false),
            new Def("tic", "clics", "Tic", 0.05, 1, -6, false),
            new Def("pop", "clics", "Pop", 0.12, 1, -6, false),
            new Def("interruptor-encender", "clics", "Interruptor: encender", 0.15, 1, -6, false),
            new Def("interruptor-apagar", "clics", "Interruptor: apagar", 0.15, 1, -6, false),
            new Def("clic-suave", "clics", "Clic suave", 0.08, 1, -6, false),
            new Def("tecla", "clics", "Tecla", 0.07, 1, -6, false),
            new Def("burbuja", "clics", "Burbuja", 0.15, 1, -6, false),

            new Def("barrido-ascendente", "transiciones", "Barrido ascendente", 1.5, 2, -3, false),
            new Def("barrido-descendente", "transiciones", "Barrido descendente", 1.5, 2, -3, false),
            new Def("reverso", "transiciones", "Reverso", 2.0, 2, -3, false),
            new Def("glitch", "transiciones", "Glitch", 0.6, 2, -3, false),
            new Def("cremallera", "transiciones", "Cremallera", 0.5, 1, -3, false),
            new Def("destello", "transiciones", "Destello", 1.2, 2, -3, false),

            new Def("campanita", "notificaciones", "Campanita", 1.2, 1, -4, false),
            new Def("ding-doble", "notificaciones", "Ding doble", 1.0, 1, -4, false),
            new Def("alerta-suave", "notificaciones", "Alerta suave", 1.0, 1, -4, false),
            new Def("exito", "notificaciones", "Éxito", 0.9, 1, -4, false),
            new Def("error", "notificaciones", "Error", 0.7, 1, -4, false),
            new Def("mensaje", "notificaciones", "Mensaje", 0.5, 1, -4, false),
            new Def("recordatorio", "notificaciones", "Recordatorio", 1.5, 1, -4, false),

            new Def("riser-3s", "risers", "Riser de 3 s", 3, 2, -3, false),
            new Def("riser-5s", "risers", "Riser de 5 s", 5, 2, -3, false),
            new Def("riser-8s", "risers", "Riser de 8 s", 8, 2, -3, false),
            new Def("riser-tonal-5s", "risers", "Riser tonal de 5 s", 5, 2, -3, false),

            new Def("impacto-cine", "impactos", "Impacto cinematográfico", 3.0, 2, -2, false),
            new Def("boom", "impactos", "Boom", 2.5, 2, -2, false),
            new Def("golpe-metalico", "impactos", "Golpe metálico", 2.0, 2, -3, false),
            new Def("impacto-sub", "impactos", "Impacto sub", 2.0, 1, -2, false),
            new Def("impacto-seco", "impactos", "Impacto seco", 1.0, 2, -2, false),
            new Def("trueno-lejano", "impactos", "Trueno lejano", 4.0, 2, -3, false),

            new Def("lluvia", "ambientes", "Lluvia", 10, 2, -12, true),
            new Def("viento", "ambientes", "Viento", 10, 2, -12, true),
            new Def("sala", "ambientes", "Tono de sala", 10, 2, -20, true),
            new Def("zumbido-electrico", "ambientes", "Zumbido eléctrico", 10, 2, -18, true),
            new Def("ventilador", "ambientes", "Ventilador", 10, 2, -14, true),
        };

        static readonly Dictionary<string, string> Label = new Dictionary<string, string>
        {
            { "golpes", "Golpe" }, { "swooshes", "Swoosh" }, { "clics", "Clic de interfaz" }, { "transiciones", "Transición" },
            { "notificaciones", "Notificación" }, { "risers", "Riser" }, { "impactos", "Impacto" }, { "ambientes", "Ambiente en bucle" },
        };

        public static string Description(Def d)
        {
            return Label[d.Cat] + " · " + d.Dur.ToString("0.##", CultureInfo.InvariantCulture).Replace('.', ',') + " s";
        }

        static int S(double sec) { return (int)Math.Round(sec * Fs); }

        // ---------- Piezas ----------

        static double Saw4(double ph) { return Math.Sin(ph) + Math.Sin(2 * ph) / 2 + Math.Sin(3 * ph) / 3 + Math.Sin(4 * ph) / 4; }

        // Seno que baja de f0 a f1 mientras decae: bombos, booms.
        static void Kick(Snd s, double at, double f0, double f1, double tp, double ta, double gain, double pan)
        {
            int i0 = S(at); double ph = 0;
            for (int i = i0; i < s.N; i++)
            {
                double t = (i - i0) / (double)Fs;
                double a = Math.Exp(-t / ta) * Math.Min(1, t / 0.001);
                if (a < 1e-6 && t > 0.01) break;
                ph += Tau * (f1 + (f0 - f1) * Math.Exp(-t / tp)) / Fs;
                s.Add(i, gain * a * Math.Sin(ph), pan);
            }
        }

        static void Tone(Snd s, double at, double f, double tau, double gain, double pan, double attack)
        {
            int i0 = S(at); double ph = 0;
            for (int i = i0; i < s.N; i++)
            {
                double t = (i - i0) / (double)Fs;
                double a = Math.Exp(-t / tau) * (attack > 0 ? Math.Min(1, t / attack) : 1);
                if (a < 1e-6 && t > attack) break;
                ph += Tau * f / Fs;
                s.Add(i, gain * a * Math.Sin(ph), pan);
            }
        }

        // Modulación de frecuencia con índice que decae: campanas y blips brillantes.
        static void Fm(Snd s, double at, double fc, double ratio, double index, double tauI, double tau, double gain, double pan, double attack)
        {
            int i0 = S(at); double pc = 0, pm = 0;
            for (int i = i0; i < s.N; i++)
            {
                double t = (i - i0) / (double)Fs;
                double a = Math.Exp(-t / tau) * Math.Min(1, t / attack);
                if (a < 1e-6 && t > attack) break;
                pm += Tau * fc * ratio / Fs; pc += Tau * fc / Fs;
                s.Add(i, gain * a * Math.Sin(pc + index * Math.Exp(-t / tauI) * Math.Sin(pm)), pan);
            }
        }

        static void Noise(Snd s, Rng r, double at, int type, double f, double q, double tau, double gain, double pan, double dur)
        {
            Bq b = Bq.Of(type, f, q); int i0 = S(at), i1 = Math.Min(s.N, i0 + S(dur));
            for (int i = i0; i < i1; i++)
            {
                double t = (i - i0) / (double)Fs;
                s.Add(i, gain * Math.Exp(-t / tau) * Math.Min(1, t / 0.0005) * b.P(r.White()), pan);
            }
        }

        static readonly double[] BellRatios = { 1, 2.01, 2.76, 4.1, 5.43 };
        static readonly double[] BellAmps = { 0.6, 0.3, 0.22, 0.12, 0.08 };
        static readonly double[] BellTaus = { 1, 0.65, 0.5, 0.33, 0.25 };

        static void Bell(Snd s, double at, double f, double tau, double gain, double pan)
        {
            for (int k = 0; k < BellRatios.Length; k++) Tone(s, at, f * BellRatios[k], tau * BellTaus[k], gain * BellAmps[k], pan, 0.002);
        }

        // Ruido por un pasa banda que barre f0 → fp → f1, con la envolvente en su punto más alto en peak (0 a 1).
        static void Swoosh(Snd s, Rng r, double at, double dur, double f0, double fp, double f1, double q, double peak,
            double pan0, double pan1, bool pink, double gain)
        {
            Bq b = new Bq(); Pink pk = new Pink(); int i0 = S(at), n = S(dur);
            for (int j = 0; j < n && i0 + j < s.N; j++)
            {
                double u = j / (double)n;
                double f = u < peak ? f0 * Math.Pow(fp / f0, u / peak) : fp * Math.Pow(f1 / fp, (u - peak) / (1 - peak));
                if ((j & 7) == 0) b.Set(2, f, q);
                double e = u < peak ? Math.Pow(u / peak, 2) : Math.Pow((1 - u) / (1 - peak), 1.5);
                double x = pink ? pk.Next(r) * 3 : r.White();
                s.Add(i0 + j, gain * e * b.P(x), pan0 + (pan1 - pan0) * u);
            }
        }

        static void Sweep(Snd s, Rng r, double f0, double f1)
        {
            Rng r2 = new Rng("barrido-r" + f0);
            Bq bl = new Bq(), br = new Bq(); double p1 = 0, p2 = 0;
            for (int i = 0; i < s.N; i++)
            {
                double u = i / (double)s.N, f = f0 * Math.Pow(f1 / f0, u);
                if ((i & 7) == 0) { bl.Set(2, f * 3, 3); br.Set(2, f * 3.1, 3); }
                double e = Math.Pow(Math.Sin(Math.PI * u), 0.8);
                p1 += Tau * f / Fs; p2 += Tau * f * 1.007 / Fs;
                s.L[i] += e * (0.35 * Saw4(p1) + 0.8 * bl.P(r.White()));
                s.R[i] += e * (0.35 * Saw4(p2) + 0.8 * br.P(r2.White()));
            }
        }

        static void Riser(Snd s, Rng r, double tonal)
        {
            Rng r2 = new Rng("riser-r" + s.N);
            Bq hl = new Bq(), hr = new Bq(), bl = new Bq(), br = new Bq(); double p1 = 0, p2 = 0, p3 = 0;
            for (int i = 0; i < s.N; i++)
            {
                double u = i / (double)s.N, fc = 200 * Math.Pow(40, u);
                if ((i & 15) == 0) { hl.Set(1, fc, 0.7); hr.Set(1, fc * 1.03, 0.7); bl.Set(2, fc * 1.5, 2); br.Set(2, fc * 1.55, 2); }
                double e = u * u * (0.3 + 0.7 * u), nl = r.White(), nr = r2.White(), f = 110 * Math.Pow(8, u);
                p1 += Tau * f / Fs; p2 += Tau * f * 1.006 / Fs; p3 += Tau * f * 1.5 / Fs;
                s.L[i] += e * (0.6 * hl.P(nl) + 0.8 * bl.P(nl) + tonal * 0.25 * (Saw4(p1) + 0.5 * Math.Sin(p3)));
                s.R[i] += e * (0.6 * hr.P(nr) + 0.8 * br.P(nr) + tonal * 0.25 * (Saw4(p2) + 0.5 * Math.Sin(p3)));
            }
        }

        // Cuadrada suave (armónicos impares) con ataque y caída cortos.
        static void Buzz(Snd s, double at, double f, double len, double gain)
        {
            int i0 = S(at); Bq lp = Bq.Of(0, 2000, 0.7); double ph = 0;
            for (int i = i0; i < Math.Min(s.N, i0 + S(len)); i++)
            {
                double t = (i - i0) / (double)Fs;
                double e = Math.Min(1, t / 0.005) * Math.Min(1, (len - t) / 0.02);
                ph += Tau * f / Fs;
                double v = Math.Sin(ph) + Math.Sin(3 * ph) / 3 + Math.Sin(5 * ph) / 5 + Math.Sin(7 * ph) / 7;
                s.Add(i, gain * e * lp.P(v), 0);
            }
        }

        // Reverberación de Schroeder: cuatro peines con amortiguación y dos pasatodo. offset descorrelaciona los canales.
        static void Reverb(double[] x, int offset, double fb, double damp, double mix)
        {
            if (x == null) return;
            int[] cd = { 1687 + offset, 1601 + offset, 2053 + offset, 2251 + offset };
            int[] ad = { 347 + offset / 3, 113 + offset / 7 };
            var cb = new double[4][]; var ci = new int[4]; var lp = new double[4];
            for (int c = 0; c < 4; c++) cb[c] = new double[cd[c]];
            var ab = new double[2][]; var ai = new int[2];
            for (int a = 0; a < 2; a++) ab[a] = new double[ad[a]];
            for (int i = 0; i < x.Length; i++)
            {
                double inp = x[i], y = 0;
                for (int c = 0; c < 4; c++)
                {
                    double o = cb[c][ci[c]];
                    lp[c] = o * (1 - damp) + lp[c] * damp;
                    cb[c][ci[c]] = inp + lp[c] * fb;
                    ci[c] = (ci[c] + 1) % cd[c];
                    y += o;
                }
                y *= 0.25;
                for (int a = 0; a < 2; a++)
                {
                    double o = ab[a][ai[a]], v = -0.6 * y + o;
                    ab[a][ai[a]] = y + 0.6 * o;
                    ai[a] = (ai[a] + 1) % ad[a];
                    y = v;
                }
                x[i] = inp + y * mix;
            }
        }

        static void Verb(Snd s, double fb, double damp, double mix)
        {
            Reverb(s.L, 0, fb, damp, mix);
            Reverb(s.R, 23, fb, damp, mix);
        }

        // ---------- Los sonidos ----------

        static void Make(Def d, Snd s, Rng r)
        {
            switch (d.Id)
            {
                case "golpe-bombo":
                    Kick(s, 0, 160, 48, 0.035, 0.18, 1, 0);
                    Noise(s, r, 0, 1, 3000, 0.7, 0.002, 0.4, 0, 0.01);
                    break;
                case "golpe-seco":
                    Noise(s, r, 0, 2, 1500, 1.2, 0.025, 1.2, 0, 0.25);
                    Tone(s, 0, 190, 0.04, 0.6, 0, 0.0005);
                    break;
                case "golpe-grave":
                    Kick(s, 0, 90, 38, 0.06, 0.35, 1, 0);
                    Tone(s, 0, 38, 0.4, 0.4, 0, 0.004);
                    break;
                case "golpe-madera":
                    Tone(s, 0, 420, 0.05, 0.8, 0, 0.0005);
                    Tone(s, 0, 980, 0.03, 0.5, 0, 0.0005);
                    Tone(s, 0, 1730, 0.02, 0.3, 0, 0.0005);
                    Noise(s, r, 0, 2, 2500, 1, 0.003, 0.6, 0, 0.02);
                    break;
                case "palmada":
                {
                    double[] at = { 0, 0.008, 0.017, 0.027 };
                    for (int k = 0; k < at.Length; k++) Noise(s, r, at[k], 2, 1200, 1.5, k == 3 ? 0.08 : 0.006, 1.5, 0, 0.35);
                    Verb(s, 0.5, 0.4, 0.15);
                    break;
                }
                case "golpe-caja":
                    Tone(s, 0, 185, 0.05, 0.7, 0, 0.0005);
                    Tone(s, 0, 330, 0.03, 0.3, 0, 0.0005);
                    Noise(s, r, 0, 1, 2000, 0.7, 0.12, 0.8, 0, 0.4);
                    break;

                case "swoosh-corto": Swoosh(s, r, 0, 0.4, 600, 3500, 1200, 1.5, 0.55, -0.2, 0.2, false, 1); break;
                case "swoosh-medio": Swoosh(s, r, 0, 0.7, 400, 2800, 900, 1.2, 0.6, -0.3, 0.3, false, 1); break;
                case "swoosh-largo": Swoosh(s, r, 0, 1.2, 300, 2400, 700, 1, 0.6, -0.4, 0.4, false, 1); break;
                case "swoosh-izquierda-derecha": Swoosh(s, r, 0, 0.8, 500, 3000, 1000, 1.3, 0.55, -0.9, 0.9, false, 1); break;
                case "swoosh-derecha-izquierda": Swoosh(s, r, 0, 0.8, 500, 3000, 1000, 1.3, 0.55, 0.9, -0.9, false, 1); break;
                case "whoosh-grave": Swoosh(s, r, 0, 1.0, 120, 900, 200, 0.9, 0.6, -0.2, 0.2, true, 1); break;
                case "whoosh-aire": Swoosh(s, r, 0, 1.5, 800, 6000, 2000, 0.8, 0.5, -0.5, 0.5, false, 1); break;
                case "swoosh-doble":
                    Swoosh(s, r, 0, 0.42, 600, 3200, 1000, 1.4, 0.55, -0.6, 0.2, false, 1);
                    Swoosh(s, r, 0.45, 0.45, 700, 3600, 1100, 1.4, 0.55, 0.6, -0.2, false, 1);
                    break;

                case "clic":
                    Noise(s, r, 0, 1, 3000, 0.7, 0.002, 1, 0, 0.02);
                    Tone(s, 0, 2200, 0.004, 0.5, 0, 0.0003);
                    break;
                case "tic": Tone(s, 0, 4200, 0.006, 1, 0, 0.0003); break;
                case "pop":
                {
                    double ph = 0;
                    for (int i = 0; i < s.N; i++)
                    {
                        double t = i / (double)Fs;
                        ph += Tau * (300 + 600 * Math.Exp(-t / 0.01)) / Fs;
                        s.L[i] += Math.Exp(-t / 0.02) * Math.Min(1, t / 0.001) * Math.Sin(ph);
                    }
                    break;
                }
                case "interruptor-encender":
                    Tone(s, 0, 900, 0.015, 1, 0, 0.0005); Tone(s, 0.05, 1300, 0.015, 1, 0, 0.0005);
                    break;
                case "interruptor-apagar":
                    Tone(s, 0, 1300, 0.015, 1, 0, 0.0005); Tone(s, 0.05, 900, 0.015, 1, 0, 0.0005);
                    break;
                case "clic-suave":
                    Tone(s, 0, 1200, 0.008, 1, 0, 0.0005);
                    Noise(s, r, 0, 0, 2500, 0.7, 0.004, 0.3, 0, 0.03);
                    break;
                case "tecla":
                    Noise(s, r, 0, 2, 4000, 2, 0.004, 1.5, 0, 0.03);
                    Noise(s, r, 0.025, 2, 1500, 2, 0.006, 0.9, 0, 0.03);
                    break;
                case "burbuja":
                {
                    double ph = 0;
                    for (int i = 0; i < s.N; i++)
                    {
                        double t = i / (double)Fs;
                        if (t > 0.12) break;
                        ph += Tau * (400 + 1000 * Math.Pow(t / 0.12, 1.5)) / Fs;
                        s.L[i] += Math.Sin(Math.PI * t / 0.12) * Math.Sin(ph);
                    }
                    break;
                }

                case "barrido-ascendente": Sweep(s, r, 200, 1600); break;
                case "barrido-descendente": Sweep(s, r, 1600, 200); break;
                case "reverso":
                {
                    var tmp = new Snd(s.N, 2);
                    Noise(tmp, r, 0, 2, 900, 0.6, 0.15, 1.2, -0.3, 0.6);
                    Noise(tmp, r, 0, 2, 2500, 0.8, 0.1, 0.8, 0.3, 0.5);
                    Kick(tmp, 0, 120, 50, 0.05, 0.3, 0.8, 0);
                    Verb(tmp, 0.86, 0.3, 0.9);
                    for (int i = 0; i < s.N; i++) { s.L[i] = tmp.L[s.N - 1 - i]; s.R[i] = tmp.R[s.N - 1 - i]; }
                    break;
                }
                case "glitch":
                {
                    double t = 0;
                    while (t < 0.57)
                    {
                        double len = 0.02 + 0.04 * r.Next(), pan = r.White() * 0.8, kind = r.Next(), f = 200 + 1800 * r.Next();
                        int i0 = S(t), n = S(len), fade = S(0.001);
                        double ph = 0; Bq b = Bq.Of(2, f * 2, 1.5);
                        for (int j = 0; j < n; j++)
                        {
                            double e = Math.Min(1, Math.Min(j, n - 1 - j) / (double)fade);
                            ph += Tau * f / Fs;
                            double v = kind < 0.4 ? Math.Sign(Math.Sin(ph)) * 0.4
                                : kind < 0.75 ? b.P(r.White()) * 1.5
                                : kind < 0.9 ? Math.Round(Math.Sin(ph) * 3) / 3 * 0.6 : 0;
                            s.Add(i0 + j, e * v, pan);
                        }
                        t += len;
                    }
                    break;
                }
                case "cremallera":
                {
                    double t = 0;
                    while (t < 0.47)
                    {
                        double u = t / 0.47;
                        Noise(s, r, t, 2, 1000 + 3000 * u, 4, 0.004, 1.5, 0, 0.012);
                        t += 1 / (25 + 65 * u);
                    }
                    break;
                }
                case "destello":
                {
                    double[] fc = { 880, 1320, 1760, 2640 };
                    for (int k = 0; k < 4; k++) Fm(s, k * 0.08, fc[k], 1.41, 3, 0.3, 0.45, 0.4, -0.6 + 0.4 * k, 0.003);
                    Verb(s, 0.8, 0.35, 0.5);
                    break;
                }

                case "campanita": Bell(s, 0, 1568, 0.6, 1, 0); Verb(s, 0.6, 0.4, 0.15); break;
                case "ding-doble": Bell(s, 0, 1318, 0.4, 1, 0); Bell(s, 0.18, 1760, 0.5, 1, 0); break;
                case "alerta-suave":
                    foreach (double at in new[] { 0.0, 0.45 }) { Tone(s, at, 660, 0.25, 0.5, 0, 0.02); Tone(s, at, 880, 0.25, 0.5, 0, 0.02); }
                    break;
                case "exito":
                    Fm(s, 0, 1047, 2, 1, 0.1, 0.25, 0.6, 0, 0.002);
                    Fm(s, 0.09, 1319, 2, 1, 0.1, 0.25, 0.6, 0, 0.002);
                    Fm(s, 0.18, 1568, 2, 1, 0.1, 0.45, 0.6, 0, 0.002);
                    break;
                case "error": Buzz(s, 0, 220, 0.18, 0.8); Buzz(s, 0.25, 185, 0.3, 0.8); break;
                case "mensaje":
                    Fm(s, 0, 1046, 3, 1.5, 0.05, 0.08, 0.7, 0, 0.002);
                    Fm(s, 0.08, 1568, 3, 1.5, 0.05, 0.15, 0.7, 0, 0.002);
                    break;
                case "recordatorio":
                {
                    double[] f = { 784, 988, 784 }, at = { 0, 0.25, 0.5 }, tau = { 0.35, 0.35, 0.5 };
                    for (int k = 0; k < 3; k++) { Tone(s, at[k], f[k], tau[k], 0.8, 0, 0.002); Tone(s, at[k], f[k] * 4, 0.05, 0.25, 0, 0.001); }
                    break;
                }

                case "riser-3s": case "riser-5s": case "riser-8s": Riser(s, r, 0.3); break;
                case "riser-tonal-5s": Riser(s, r, 1.5); break;

                case "impacto-cine":
                    Kick(s, 0, 55, 32, 0.15, 0.6, 1, 0);
                    Noise(s, r, 0, 0, 400, 0.7, 0.25, 1.2, 0, 2);
                    Noise(s, r, 0, 1, 2000, 0.7, 0.03, 0.8, 0, 0.2);
                    Verb(s, 0.84, 0.45, 0.35);
                    break;
                case "boom":
                    Kick(s, 0, 70, 30, 0.2, 0.7, 1, 0);
                    Noise(s, r, 0, 0, 150, 0.7, 0.5, 2, 0, 2.5);
                    Verb(s, 0.7, 0.5, 0.2);
                    break;
                case "golpe-metalico":
                {
                    double[] ratio = { 1, 1.47, 2.09, 2.56, 3.39, 4.07, 5.21 }, tau = { 1.2, 0.9, 0.8, 0.6, 0.5, 0.4, 0.3 };
                    for (int k = 0; k < ratio.Length; k++)
                    {
                        Tone(s, 0, 310 * ratio[k], tau[k] / 2.5, 0.5 / (1 + k * 0.3), -0.3, 0.0005);
                        Tone(s, 0, 310 * ratio[k] * 1.004, tau[k] / 2.5, 0.5 / (1 + k * 0.3), 0.3, 0.0005);
                    }
                    Noise(s, r, 0, 1, 3000, 0.7, 0.01, 0.8, 0, 0.05);
                    break;
                }
                case "impacto-sub":
                    Kick(s, 0, 45, 28, 0.2, 0.8, 1, 0);
                    Noise(s, r, 0, 2, 1200, 1, 0.003, 0.3, 0, 0.02);
                    break;
                case "impacto-seco":
                    Kick(s, 0, 140, 45, 0.04, 0.2, 1, 0);
                    Noise(s, r, 0, 2, 1800, 0.8, 0.05, 1.2, 0, 0.4);
                    Verb(s, 0.65, 0.4, 0.25);
                    break;
                case "trueno-lejano":
                {
                    Brown bl = new Brown(), br = new Brown(); Rng r2 = new Rng("trueno-r");
                    Bq ll = Bq.Of(0, 200, 0.7), lr = Bq.Of(0, 220, 0.7);
                    double[] at = { 0, 0.3, 0.9, 1.6 }, tau = { 0.3, 0.5, 0.7, 0.8 }, g = { 0.6, 1, 0.8, 0.5 };
                    for (int i = 0; i < s.N; i++)
                    {
                        double t = i / (double)Fs, e = 0;
                        for (int k = 0; k < at.Length; k++) if (t >= at[k]) e += g[k] * Math.Min(1, (t - at[k]) / 0.03) * Math.Exp(-(t - at[k]) / tau[k]);
                        s.L[i] += e * ll.P(bl.Next(r)); s.R[i] += e * lr.P(br.Next(r2));
                    }
                    Verb(s, 0.8, 0.6, 0.3);
                    break;
                }

                case "lluvia":
                {
                    Pink pl = new Pink(), pr = new Pink(); Rng r2 = new Rng("lluvia-r");
                    Bq hl = Bq.Of(1, 500, 0.7), hr = Bq.Of(1, 500, 0.7), ll = Bq.Of(0, 7000, 0.7), lr = Bq.Of(0, 7000, 0.7);
                    for (int i = 0; i < s.N; i++) { s.L[i] += 0.5 * ll.P(hl.P(pl.Next(r))); s.R[i] += 0.5 * lr.P(hr.P(pr.Next(r2))); }
                    int drops = (int)(s.N / (double)Fs * 60);
                    for (int k = 0; k < drops; k++)
                        Noise(s, r, r.Next() * (s.N / (double)Fs - 0.02), 2, 2000 + 4000 * r.Next(), 3, 0.003, 0.3 + 0.4 * r.Next(), r.White(), 0.015);
                    break;
                }
                case "viento":
                {
                    Pink pl = new Pink(), pr = new Pink(); Rng r2 = new Rng("viento-r"); Bq bl = new Bq(), br = new Bq();
                    for (int i = 0; i < s.N; i++)
                    {
                        double t = i / (double)Fs;
                        if ((i & 15) == 0)
                        {
                            bl.Set(2, 550 + 250 * (Math.Sin(Tau * 0.07 * t) + 0.5 * Math.Sin(Tau * 0.13 * t + 1)), 0.8);
                            br.Set(2, 550 + 250 * (Math.Sin(Tau * 0.08 * t + 2) + 0.5 * Math.Sin(Tau * 0.12 * t)), 0.8);
                        }
                        s.L[i] += (0.6 + 0.3 * Math.Sin(Tau * 0.11 * t)) * bl.P(pl.Next(r));
                        s.R[i] += (0.6 + 0.3 * Math.Sin(Tau * 0.09 * t + 1.3)) * br.P(pr.Next(r2));
                    }
                    break;
                }
                case "sala":
                {
                    Brown bl = new Brown(), br = new Brown(); Pink pl = new Pink(), pr = new Pink(); Rng r2 = new Rng("sala-r");
                    Bq ll = Bq.Of(0, 300, 0.7), lr = Bq.Of(0, 300, 0.7), hl = Bq.Of(1, 1500, 0.7), hr = Bq.Of(1, 1500, 0.7);
                    for (int i = 0; i < s.N; i++)
                    {
                        s.L[i] += ll.P(bl.Next(r)) + 0.05 * hl.P(pl.Next(r));
                        s.R[i] += lr.P(br.Next(r2)) + 0.05 * hr.P(pr.Next(r2));
                    }
                    break;
                }
                case "zumbido-electrico":
                {
                    Bq hl = Bq.Of(1, 3000, 0.7), hr = Bq.Of(1, 3000, 0.7); Rng r2 = new Rng("zumbido-r");
                    for (int i = 0; i < s.N; i++)
                    {
                        double t = i / (double)Fs, v = 0;
                        for (int k = 1; k <= 8; k++) v += (k == 2 ? 1.2 : 1) / Math.Pow(k, 1.2) * Math.Sin(Tau * 50 * k * t);
                        double buzz = Math.Pow(Math.Abs(Math.Sin(Tau * 50 * t)), 4) * 0.05;
                        s.L[i] += v + buzz * hl.P(r.White()); s.R[i] += v + buzz * hr.P(r2.White());
                    }
                    break;
                }
                case "ventilador":
                {
                    Pink pl = new Pink(), pr = new Pink(); Rng r2 = new Rng("ventilador-r");
                    Bq ll = Bq.Of(0, 900, 0.7), lr = Bq.Of(0, 900, 0.7);
                    for (int i = 0; i < s.N; i++)
                    {
                        double t = i / (double)Fs, blade = 0.15 * (1 + 0.1 * Math.Sin(Tau * 3 * t)) * Math.Sin(Tau * 120 * t);
                        s.L[i] += ll.P(pl.Next(r)) * 2 + blade; s.R[i] += lr.P(pr.Next(r2)) * 2 + blade;
                    }
                    break;
                }
                default: throw new InvalidOperationException("Sin receta: " + d.Id);
            }
        }

        // ---------- Acabado: pasa altos de 20 Hz, bucle, sin DC, fundidos y pico ----------

        static void Fade(double[] x, int fin, int fout)
        {
            if (x == null) return;
            for (int k = 0; k < fin; k++) x[k] *= 0.5 - 0.5 * Math.Cos(Math.PI * k / fin);
            for (int k = 0; k < fout; k++) x[x.Length - 1 - k] *= 0.5 - 0.5 * Math.Cos(Math.PI * k / fout);
        }

        // La cola sobrante se funde con el principio: la última muestra queda junto a la que seguía en la síntesis.
        static double[] Loop(double[] x, int n)
        {
            if (x == null) return null;
            int xf = x.Length - n; var o = new double[n];
            for (int i = 0; i < n; i++)
            {
                if (i < xf) { double a = Math.PI / 2 * i / xf; o[i] = x[i] * Math.Sin(a) + x[n + i] * Math.Cos(a); }
                else o[i] = x[i];
            }
            return o;
        }

        static void RemoveDc(double[] x)
        {
            if (x == null) return;
            double m = 0; foreach (double v in x) m += v; m /= x.Length;
            for (int i = 0; i < x.Length; i++) x[i] -= m;
        }

        public static double[][] Render(Def d)
        {
            int n = S(d.Dur), total = d.Loop ? n + S(Crossfade) : n;
            var s = new Snd(total, d.Ch);
            Make(d, s, new Rng(d.Id));
            foreach (double[] ch in new[] { s.L, s.R })
            {
                if (ch == null) continue;
                Bq hp = Bq.Of(1, 20, 0.707);
                for (int i = 0; i < ch.Length; i++) ch[i] = hp.P(ch[i]);
            }
            double[] l = s.L, r = s.R;
            if (d.Loop) { l = Loop(l, n); r = Loop(r, n); }
            RemoveDc(l); RemoveDc(r);
            if (!d.Loop) { int fin = S(d.Cat == "clics" ? 0.001 : 0.002), fout = S(0.01); Fade(l, fin, fout); Fade(r, fin, fout); }
            double peak = 0;
            foreach (double[] ch in new[] { l, r }) if (ch != null) foreach (double v in ch) peak = Math.Max(peak, Math.Abs(v));
            double g = Math.Pow(10, d.Db / 20) / peak;
            foreach (double[] ch in new[] { l, r }) if (ch != null) for (int i = 0; i < ch.Length; i++) ch[i] *= g;
            return r == null ? new[] { l } : new[] { l, r };
        }

        public static void WriteWav(string path, double[][] ch)
        {
            int n = ch[0].Length, c = ch.Length, data = n * c * 2;
            using (var w = new BinaryWriter(File.Create(path)))
            {
                w.Write(Encoding.ASCII.GetBytes("RIFF")); w.Write(36 + data); w.Write(Encoding.ASCII.GetBytes("WAVE"));
                w.Write(Encoding.ASCII.GetBytes("fmt ")); w.Write(16); w.Write((short)1); w.Write((short)c);
                w.Write(Fs); w.Write(Fs * c * 2); w.Write((short)(c * 2)); w.Write((short)16);
                w.Write(Encoding.ASCII.GetBytes("data")); w.Write(data);
                for (int i = 0; i < n; i++)
                    for (int k = 0; k < c; k++)
                        w.Write((short)Math.Max(-32768, Math.Min(32767, Math.Round(ch[k][i] * 32767))));
            }
        }

        public static string FileOf(Def d) { return "sonidos/" + d.Cat + "/" + d.Id + ".wav"; }

        public static int WriteAll(string destino)
        {
            foreach (Def d in All)
            {
                string path = Path.Combine(destino, FileOf(d).Replace('/', Path.DirectorySeparatorChar));
                Directory.CreateDirectory(Path.GetDirectoryName(path));
                WriteWav(path, Render(d));
            }
            return All.Length;
        }

        static string Esc(string s) { return s.Replace("\\", "\\\\").Replace("\"", "\\\""); }

        public static string Manifest()
        {
            var b = new StringBuilder();
            b.Append("{\n  \"formatVersion\": 1,\n  \"id\": \"rodaje-sonidos\",\n  \"version\": \"1.0.0\",\n  \"kind\": \"content\",\n");
            b.Append("  \"name\": \"Sonidos\",\n");
            b.Append("  \"description\": \"" + All.Length + " efectos de sonido sintetizados por un script propio: golpes, swooshes, clics, transiciones, notificaciones, risers, impactos y ambientes en bucle. WAV de 48 kHz, dominio público (CC0).\",\n");
            b.Append("  \"author\": \"Dathinel\",\n  \"license\": \"CC0-1.0\",\n  \"repository\": \"https://github.com/Dathinel/rodaje-sonidos\",\n");
            b.Append("  \"apps\": [\n    \"rodaje\"\n  ],\n  \"items\": [\n");
            for (int i = 0; i < All.Length; i++)
            {
                Def d = All[i];
                b.Append("    {\n      \"id\": \"" + d.Id + "\",\n      \"kind\": \"sound\",\n      \"name\": \"" + Esc(d.Name) + "\",\n");
                b.Append("      \"file\": \"" + FileOf(d) + "\",\n      \"description\": \"" + Esc(Description(d)) + "\"\n    }");
                b.Append(i < All.Length - 1 ? ",\n" : "\n");
            }
            b.Append("  ]\n}\n");
            return b.ToString();
        }
    }
}
'@
}

$cuenta = [RodajeSonidos.Lib]::WriteAll([System.IO.Path]::GetFullPath($Destino))
Write-Host "  $cuenta sonidos en $Destino\sonidos"
if ($Manifiesto) {
    [System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($Manifiesto), [RodajeSonidos.Lib]::Manifest(), (New-Object System.Text.UTF8Encoding $false))
    Write-Host "  Manifiesto en $Manifiesto"
}
exit 0
