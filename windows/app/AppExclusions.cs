using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
namespace OpenFlux {
public sealed class AppRouter : IDisposable {
    Process process; IntPtr job; bool stopping;
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern IntPtr CreateJobObject(IntPtr attrs,string name);
    [DllImport("kernel32.dll")] static extern bool SetInformationJobObject(IntPtr job,int info,IntPtr data,uint length);
    [DllImport("kernel32.dll")] static extern bool AssignProcessToJobObject(IntPtr job,IntPtr process);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    public static string PhysicalInterface() {
        using(var socket=new Socket(AddressFamily.InterNetwork,SocketType.Dgram,ProtocolType.Udp)) {
            socket.Connect("1.1.1.1",53);
            var ip=((IPEndPoint)socket.LocalEndPoint).Address;
            var nic=NetworkInterface.GetAllNetworkInterfaces().FirstOrDefault(n=>n.OperationalStatus==OperationalStatus.Up && n.GetIPProperties().UnicastAddresses.Any(a=>a.Address.Equals(ip)));
            if(nic==null || nic.Name.StartsWith("OpenFlux",StringComparison.OrdinalIgnoreCase))throw new Exception("Не найден обычный сетевой адаптер. Отключите другой VPN и повторите.");
            return nic.Name;
        }
    }
    public static string Config(string physical,IEnumerable<string> apps) {
        var paths=apps.Select(Path.GetFullPath).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        if(paths.Length==0)throw new Exception("Не выбраны приложения для исключения.");
        return new JavaScriptSerializer().Serialize(new {
            log=new {level="info",timestamp=false},
            inbounds=new[]{new {type="tun",tag="apps",interface_name="OpenFlux Apps",address=new[]{"172.30.255.1/30"},mtu=1300,auto_route=true,strict_route=false,dns_mode="disabled",stack="gvisor",route_address=new[]{"0.0.0.0/2","64.0.0.0/2","128.0.0.0/2","192.0.0.0/2"}}},
            outbounds=new[]{new {type="direct",tag="vpn",bind_interface="OpenFlux"},new {type="direct",tag="direct",bind_interface=physical}},
            route=new {find_process=true,default_interface=physical,final="vpn",rules=new object[]{
                new {process_path=new[]{Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"openflux-core.exe")},action="route",outbound="direct"},
                new {process_path=paths,action="route",outbound="direct"}
            }}
        });
    }
    public async Task Start(string physical,string[] paths,Action failed) {
        var executable=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"openflux-router.exe");
        if(!File.Exists(executable))throw new Exception("Нет модуля исключений. Переустановите OpenFlux.");
        string config=Path.Combine(Storage.Dir,"apps-routing.json");Directory.CreateDirectory(Storage.Dir);
        File.WriteAllText(config,Config(physical,paths),new System.Text.UTF8Encoding(false));
        // Kill the routing child if the GUI crashes; no background router survives.
        job=CreateJobObject(IntPtr.Zero,null);
        IntPtr info=Marshal.AllocHGlobal(144);
        try {
            for(int i=0;i<144;i++)Marshal.WriteByte(info,i,0);
            Marshal.WriteInt32(info,16,0x2000);
            if(job==IntPtr.Zero || !SetInformationJobObject(job,9,info,144))throw new Exception("Не удалось подготовить безопасный запуск исключений.");
        } finally {Marshal.FreeHGlobal(info);}
        var started=new TaskCompletionSource<bool>();
        process=new Process {StartInfo=new ProcessStartInfo(executable,"run -c \""+config+"\""){UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true,WorkingDirectory=AppDomain.CurrentDomain.BaseDirectory},EnableRaisingEvents=true};
        DataReceivedEventHandler line=(s,e)=>{if(e.Data!=null && e.Data.Contains("sing-box started"))started.TrySetResult(true);};
        process.OutputDataReceived+=line;process.ErrorDataReceived+=line;
        process.Exited+=(s,e)=>{started.TrySetResult(false);if(!stopping)failed();};
        try {
            process.Start();
            if(!AssignProcessToJobObject(job,process.Handle))throw new Exception("Не удалось защитить завершение модуля исключений.");
            process.BeginOutputReadLine();process.BeginErrorReadLine();
            if(await Task.WhenAny(started.Task,Task.Delay(15000))!=started.Task || !await started.Task || process.HasExited)throw new Exception("Модуль исключений не запустился. VPN отключён; проверьте журнал и сетевые адаптеры.");
        } catch {Dispose();throw;}
    }
    public void Dispose() {
        stopping=true;
        if(job!=IntPtr.Zero){CloseHandle(job);job=IntPtr.Zero;}
        if(process!=null){try{if(!process.HasExited){process.Kill();process.WaitForExit(3000);}}catch{}process.Dispose();process=null;}
    }
}
public partial class MainWindow {
    AppRouter appRouter;string physicalInterface;bool routerStarting,connecting;
    bool HasExclusions {get{return saved.directApps!=null && saved.directApps.Length>0;}}
    void ShowAppExclusions() {
        var p=Page("Приложения без VPN");

        var note=Text("Выбранные приложения выходят напрямую. Остальные используют VPN. Изменения применяются после переподключения. Перезапустите выбранные приложения.",14);note.TextWrapping=TextWrapping.Wrap;p.Children.Add(Card(note));
        p.Children.Add(Btn("Добавить приложение (.exe)",()=>{
            if(core!=null&&!core.HasExited){MessageBox.Show("Сначала отключите VPN.","OpenFlux");return;}
            var dlg=new Microsoft.Win32.OpenFileDialog{Filter="Приложение Windows (*.exe)|*.exe",CheckFileExists=true,Multiselect=true};
            if(dlg.ShowDialog(this)==true) {
                var paths=new HashSet<string>(saved.directApps??new string[0],StringComparer.OrdinalIgnoreCase);
                foreach(var f in dlg.FileNames)paths.Add(Path.GetFullPath(f));
                saved.directApps=paths.ToArray();Storage.Save(saved);ShowAppExclusions();
            }
        },true));
        foreach(var path in saved.directApps??new string[0]) {
            string selected=path;var box=new StackPanel();box.Children.Add(Text(Path.GetFileNameWithoutExtension(path),18));
            var location=Text(path,11);location.TextWrapping=TextWrapping.Wrap;location.Foreground=muted;box.Children.Add(location);
            box.Children.Add(Btn("Убрать из исключений",()=>{
                if(core!=null&&!core.HasExited){MessageBox.Show("Сначала отключите VPN.","OpenFlux");return;}
                saved.directApps=saved.directApps.Where(x=>!String.Equals(x,selected,StringComparison.OrdinalIgnoreCase)).ToArray();Storage.Save(saved);ShowAppExclusions();
            },false));p.Children.Add(Card(box));
        }
        if(!HasExclusions)p.Children.Add(Text("Исключений пока нет — приложения используют VPN.",13));
        var hint=Text("Для браузера выберите основной .exe. Если программа использует отдельные сетевые процессы, добавьте их тоже. DNS остаётся через VPN; поддерживается IPv4.",12);hint.TextWrapping=TextWrapping.Wrap;hint.Foreground=muted;p.Children.Add(hint);
    }
    async Task CompleteConnection() {
        if(routerStarting||ready||stopping)return;
        routerStarting=true; bool failed=false;
        try {
            if(HasExclusions) {
                appRouter=new AppRouter();var activeRouter=appRouter;
                await activeRouter.Start(physicalInterface,saved.directApps,()=>Dispatcher.BeginInvoke(new Action(async()=>{if(appRouter==activeRouter&&!stopping)await Stop("Модуль исключений остановился. Подключитесь повторно.");})));
                if(stopping||core==null||core.HasExited){activeRouter.Dispose();return;}
                AddLog("Исключения приложений включены: "+saved.directApps.Length);
            }
            ready=true;PaintState();
        } catch(Exception e){AddLog(e.Message);failed=true;}
        finally{routerStarting=false;} if(failed)await Stop("Не удалось включить исключения приложений.");
    }
    void StopAppRouter(){if(appRouter!=null){appRouter.Dispose();appRouter=null;}}
}
}
