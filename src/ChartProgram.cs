using System;
static class ChartProgram {
    [STAThread] static int Main(string[] args) {
        try { if (args.Length != 3 || args[0] != "--plot") return 2; SentimentPlot.Render(args[1], args[2]); return 0; }
        catch (Exception error) { Console.Error.WriteLine(error.Message); return 1; }
    }
}
