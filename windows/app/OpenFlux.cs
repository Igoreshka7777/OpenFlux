using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using System.Windows.Threading;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;

[assembly:System.Reflection.AssemblyTitle("OpenFlux")]
[assembly:System.Reflection.AssemblyProduct("OpenFlux")]
[assembly:System.Reflection.AssemblyVersion("1.0.1.0")]
[assembly:System.Reflection.AssemblyFileVersion("1.0.1.0")]

namespace OpenFlux {
public class Profile {
    public string host, password, hashes, token;
    public int port;
    public bool Panel { get { return host == "2.56.174.146" || host == "igoreshka7777.igoreshka777.org"; } }
    public static Profile Parse(string raw) {
        if (String.IsNullOrWhiteSpace(raw) || raw.Length > 32768) throw new Exception("Вставьте полную ссылку csqtt:// из карточки клиента.");
        raw=raw.Trim().Replace("&amp;","&");
        Uri u;
        if (!Uri.TryCreate(raw,UriKind.Absolute,out u) || u.Scheme!="csqtt" || u.Host!="connect" || u.Fragment!="" || u.UserInfo!="") throw new Exception("Нужна ссылка csqtt://connect?v=2…");
        var q=new Dictionary<string,string>();
        foreach(var part in u.Query.TrimStart('?').Split('&',';')) {
            int i=part.IndexOf('='); if(i<1) continue;
            string key=Uri.UnescapeDataString(part.Substring(0,i));
            if(q.ContainsKey(key)) throw new Exception("В ссылке повторяется параметр "+key);
            q[key]=part.Substring(i+1);
        }
        Func<string,string> read=k=>q.ContainsKey(k)?Uri.UnescapeDataString(q[k]):"";
        var p=new Profile {host=read("host").ToLowerInvariant(), password=read("password"),token=read("token")};
        if(read("v")!="2" || !Int32.TryParse(read("peer"),out p.port) || p.port<1 || p.port>65535 || Uri.CheckHostName(p.host)==UriHostNameType.Unknown || p.password.Length==0 || Regex.IsMatch(p.password+p.token,@"\s")) throw new Exception("Ссылка повреждена. Скопируйте её целиком из панели.");
        var hashes=new List<string>();
        if(q.ContainsKey("hashes") && q["hashes"]!="") foreach(string part in q["hashes"].Split('+')) {
            string h=Uri.UnescapeDataString(part);
            h=Regex.Replace(h,@"^(https?://)?(m\.)?vk\.(ru|com)/call/join/","",RegexOptions.IgnoreCase).Split('?','#')[0].TrimEnd('/');
            if(!Regex.IsMatch(h,@"^[a-zA-Z0-9_\-=]{16,512}$")) throw new Exception("В ссылке неверный адрес звонка VK.");
            if(!hashes.Contains(h)) hashes.Add(h);
        }
        if(hashes.Count>6 || (hashes.Count==0 && p.token=="")) throw new Exception("В ссылке нет хешей звонка или токена VK. Получите полную ссылку у администратора.");
        p.hashes=String.Join(",",hashes); return p;
    }
    public string Config(string id,int workers) {
        return new JavaScriptSerializer().Serialize(new {peer=(host.Contains(":")?"["+host+"]":host)+":"+port, password=password, hashes=hashes,token=token,device_id=id,workers=workers});
    }
}
public class Saved { public string link=""; public string id=Guid.NewGuid().ToString(); public int workers=18; }
public static class Storage {
    public static string Dir=System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"OpenFlux");
    public static string FileName=System.IO.Path.Combine(Dir,"profile.dat");
    public static Saved Load() { if(!File.Exists(FileName)) return new Saved(); return new JavaScriptSerializer().Deserialize<Saved>(Encoding.UTF8.GetString(ProtectedData.Unprotect(File.ReadAllBytes(FileName),null,DataProtectionScope.CurrentUser))); }
    public static void Save(Saved s) {
        Directory.CreateDirectory(Dir); byte[] data=ProtectedData.Protect(Encoding.UTF8.GetBytes(new JavaScriptSerializer().Serialize(s)),null,DataProtectionScope.CurrentUser);
        string temp=FileName+".tmp"; File.WriteAllBytes(temp,data);
        if(File.Exists(FileName)) File.Replace(temp,FileName,null); else File.Move(temp,FileName);
    }
}
public static class Redaction {
    public static string Clean(string s,Profile p) {
        if(s==null) return "";
        if(p!=null) foreach(string secret in new[]{p.password,p.token,p.hashes}) if(!String.IsNullOrEmpty(secret)) s=s.Replace(secret,"[скрыто]");
        s=Regex.Replace(s,@"https?://[^\s)]+",m=>{Uri u; return Uri.TryCreate(m.Value,UriKind.Absolute,out u)?u.GetLeftPart(UriPartial.Path):"[адрес]";});
        s=Regex.Replace(s,@"(?i)(password|token|secret|hashes)([=:\s]+)[^\s,;]+","$1$2[скрыто]");
        return s.Length>1600?s.Substring(0,1600):s;
    }
}
public class StartupBudget {
    public int SecondsLeft=180;
    public bool Tick(bool waitingForCaptcha,bool connected) {
        if(connected || waitingForCaptcha)return false;
        return --SecondsLeft<=0;
    }
}
public class MainWindow : Window {
    [System.Runtime.InteropServices.DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd,int attr,ref int value,int size);
    readonly Brush bg=new SolidColorBrush(Color.FromRgb(10,10,12)), fg=new SolidColorBrush(Color.FromRgb(247,246,246));
    readonly Brush muted=new SolidColorBrush(Color.FromRgb(155,151,160)), orange=new SolidColorBrush(Color.FromRgb(255,130,38));
    readonly JavaScriptSerializer json=new JavaScriptSerializer();
    Saved saved; Profile current; Process core; bool stopping,closeAfter,ready,preview,apiBusy,captchaBusy;
    int generation; DateTime started; Window captcha;
    Grid content; TextBlock state,hint,traffic,subscription,saveHint,chatHint; Ellipse ring; Button power;
    PasswordBox link; TextBox shownLink,chatText,logBox; Slider workers; StackPanel chatMessages;
    readonly List<string> logs=new List<string>();
    string stopReason="", lastLog="", lastLogTime="";
    int repetitions;
    bool logDirty;
    readonly DispatcherTimer logRefresh=new DispatcherTimer();
    readonly DispatcherTimer poll=new DispatcherTimer();
    System.Windows.Forms.NotifyIcon tray;
    bool noticesBusy;
    readonly HashSet<int> noticesShown=new HashSet<int>();
    public MainWindow(bool isPreview) {
        preview=isPreview; Title="OpenFlux"; Width=540;Height=780;MinWidth=460;MinHeight=660;
        Background=bg;Foreground=fg;FontFamily=new FontFamily("Segoe UI");FontSize=14;
        WindowStartupLocation=WindowStartupLocation.CenterScreen;
        SourceInitialized+=(s,e)=>{int dark=1;try{DwmSetWindowAttribute(new System.Windows.Interop.WindowInteropHelper(this).Handle,20,ref dark,4);}catch{}};
        Icon=BitmapFrame.Create(new Uri(System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"OpenFlux.png")));
        Resources=(ResourceDictionary)XamlReader.Parse(@"<ResourceDictionary xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'>
<Style TargetType='Button'><Setter Property='Background' Value='#29262E'/><Setter Property='Foreground' Value='#FFFFFF'/><Setter Property='BorderThickness' Value='0'/><Setter Property='Padding' Value='20,12'/><Setter Property='FontWeight' Value='SemiBold'/><Setter Property='Cursor' Value='Hand'/><Setter Property='Margin' Value='0,4,0,4'/><Setter Property='Template'><Setter.Value><ControlTemplate TargetType='Button'><Border x:Name='B' Background='{TemplateBinding Background}' CornerRadius='15' Padding='{TemplateBinding Padding}'><ContentPresenter HorizontalAlignment='Center' VerticalAlignment='Center'/></Border><ControlTemplate.Triggers><Trigger Property='IsMouseOver' Value='True'><Setter TargetName='B' Property='Opacity' Value='.82'/></Trigger><Trigger Property='IsEnabled' Value='False'><Setter TargetName='B' Property='Opacity' Value='.45'/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
<Style TargetType='TextBox'><Setter Property='Background' Value='#17151B'/><Setter Property='Foreground' Value='White'/><Setter Property='CaretBrush' Value='White'/><Setter Property='BorderBrush' Value='#49434E'/><Setter Property='Padding' Value='12'/><Setter Property='SelectionBrush' Value='#F47D24'/><Setter Property='FontSize' Value='14'/></Style>
<Style TargetType='PasswordBox'><Setter Property='Background' Value='#17151B'/><Setter Property='Foreground' Value='White'/><Setter Property='CaretBrush' Value='White'/><Setter Property='BorderBrush' Value='#49434E'/><Setter Property='Padding' Value='12'/></Style>
<Style TargetType='ScrollBar'><Setter Property='Width' Value='8'/><Setter Property='Template'><Setter.Value><ControlTemplate TargetType='ScrollBar'><Grid Background='#0A0A0C'><Track x:Name='PART_Track' IsDirectionReversed='True'><Track.DecreaseRepeatButton><RepeatButton Command='ScrollBar.PageUpCommand' Opacity='0'/></Track.DecreaseRepeatButton><Track.Thumb><Thumb><Thumb.Template><ControlTemplate TargetType='Thumb'><Border Background='#49434E' CornerRadius='4' Margin='2,0'/></ControlTemplate></Thumb.Template></Thumb></Track.Thumb><Track.IncreaseRepeatButton><RepeatButton Command='ScrollBar.PageDownCommand' Opacity='0'/></Track.IncreaseRepeatButton></Track></Grid></ControlTemplate></Setter.Value></Setter></Style></ResourceDictionary>");
        try { saved=preview?new Saved():Storage.Load(); } catch { saved=new Saved(); AddLog("Не удалось прочитать сохранённую ссылку. Вставьте её заново."); }
        if(!preview) { try { Storage.Save(saved); } catch { AddLog("Не удалось сохранить настройки компьютера."); } }
        var root=new Grid {Margin=new Thickness(28,18,28,24)}; root.RowDefinitions.Add(new RowDefinition{Height=GridLength.Auto});root.RowDefinitions.Add(new RowDefinition());
        var header=new DockPanel{Margin=new Thickness(0,0,0,20)};
        var settings=Btn("\uE713",()=>ShowSettings(),false); settings.FontFamily=new FontFamily("Segoe MDL2 Assets");settings.FontSize=23;settings.Padding=new Thickness(12,9,12,9);DockPanel.SetDock(settings,Dock.Right);header.Children.Add(settings);
        var logo=Text("",22);logo.Inlines.Add(new Run("●  "){Foreground=orange});logo.Inlines.Add("O P E N F L U X");logo.FontWeight=FontWeights.Bold;logo.VerticalAlignment=VerticalAlignment.Center;header.Children.Add(logo);
        content=new Grid();Grid.SetRow(content,1);root.Children.Add(header);root.Children.Add(content);Content=root;
        Closing+=async (s,e)=>{ if(core!=null && !core.HasExited) {e.Cancel=true;closeAfter=true;await Stop("Приложение закрыто");} else {poll.Stop();logRefresh.Stop();if(tray!=null)tray.Dispose();} };
        if(!preview) {
            tray=new System.Windows.Forms.NotifyIcon {Icon=new System.Drawing.Icon(System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"OpenFlux.ico")),Text="OpenFlux",Visible=true};
            tray.DoubleClick+=(s,e)=>{Show();WindowState=WindowState.Normal;Activate();};
            tray.BalloonTipClicked+=(s,e)=>{Show();WindowState=WindowState.Normal;Activate();ShowChat();};
            poll.Interval=TimeSpan.FromSeconds(20);poll.Tick+=async(s,e)=>{await RefreshSubscription(false);if(ready)await Notices();if(chatMessages!=null)await LoadChat();};poll.Start();
        }
        if(!preview) {
            string path=System.IO.Path.Combine(Storage.Dir,"last-session.log");
            try {if(File.Exists(path))logs.AddRange(File.ReadAllLines(path).Reverse().Take(2000).Reverse());}catch{}
            logRefresh.Interval=TimeSpan.FromMilliseconds(250);
            logRefresh.Tick+=(s,e)=>{if(logDirty && logBox!=null){logBox.Text=String.Join(Environment.NewLine,logs);logBox.ScrollToEnd();logDirty=false;}};
            logRefresh.Start();
        }
        if(saved.link=="") ShowWelcome();else ShowHome();
    }
    TextBlock Text(string s,double size=14) {return new TextBlock{Text=s,FontSize=size,TextWrapping=TextWrapping.Wrap,Foreground=fg};}
    Button Btn(string title,Action action,bool primary) {var b=new Button{Content=title};if(primary)b.Background=new LinearGradientBrush(Color.FromRgb(247,71,38),Color.FromRgb(255,134,14),0);b.Click+=(s,e)=>action();return b;}
    Border Card(UIElement c) {return new Border{Background=new SolidColorBrush(Color.FromRgb(24,22,28)),CornerRadius=new CornerRadius(22),Padding=new Thickness(22),Margin=new Thickness(0,12,0,8),Child=c};}
    StackPanel Page(string title) {content.Children.Clear();chatMessages=null;logBox=null;subscription=null;var stack=new StackPanel();var back=Btn("←  Назад",()=>ShowHome(),false);back.HorizontalAlignment=HorizontalAlignment.Left;stack.Children.Add(back);stack.Children.Add(Text(title,27));content.Children.Add(new ScrollViewer{Content=stack,VerticalScrollBarVisibility=ScrollBarVisibility.Auto});return stack;}
    void ShowWelcome() {var p=Page("Добро пожаловать");p.Children.Add(Text("Ваш OpenFlux для Windows",19));p.Children.Add(Card(Text("Вставьте личную ссылку подключения. Она сохранится на этом компьютере.")));p.Children.Add(Btn("ДОБАВИТЬ ССЫЛКУ",()=>ShowSettings(),true));p.Children.Add(Btn("ПОЛУЧИТЬ ДОСТУП",()=>OpenUrl("https://193.233.223.211/get"),false));}
    void ShowHome() {
        content.Children.Clear();chatMessages=null;subscription=null;logBox=null;
        var grid=new Grid();grid.RowDefinitions.Add(new RowDefinition{Height=new GridLength(1,GridUnitType.Star)});grid.RowDefinitions.Add(new RowDefinition{Height=GridLength.Auto});grid.RowDefinitions.Add(new RowDefinition{Height=new GridLength(1,GridUnitType.Star)});
        hint=Text("",15);hint.Foreground=muted;hint.TextAlignment=TextAlignment.Center;hint.VerticalAlignment=VerticalAlignment.Bottom;hint.Margin=new Thickness(10,0,10,26);grid.Children.Add(hint);
        var circle=new Grid {Width=240,Height=240,Margin=new Thickness(10)};ring=new Ellipse{Stroke=muted,StrokeThickness=2.5,Margin=new Thickness(14)};circle.Children.Add(ring);
        power=Btn("⏻",async()=>{if(core!=null&&!core.HasExited)await Stop();else await Connect();},false);power.Background=Brushes.Transparent;power.FontSize=68;power.FontWeight=FontWeights.Light;power.Foreground=muted;power.Width=195;power.Height=195;circle.Children.Add(power);Grid.SetRow(circle,1);grid.Children.Add(circle);
        var bottom=new StackPanel{Margin=new Thickness(0,25,0,0)};state=Text("ОТКЛЮЧЕНО",21);state.FontWeight=FontWeights.Bold;state.TextAlignment=TextAlignment.Center;bottom.Children.Add(state);
        traffic=Text("",13);traffic.Foreground=muted;traffic.TextAlignment=TextAlignment.Center;traffic.Margin=new Thickness(0,15,0,18);bottom.Children.Add(traffic);
        var support=Btn("Поддержка",()=>ShowChat(),false);support.HorizontalAlignment=HorizontalAlignment.Center;bottom.Children.Add(support);Grid.SetRow(bottom,2);grid.Children.Add(bottom);content.Children.Add(grid);PaintState();
    }
    void PaintState() {
        bool running=core!=null&&!core.HasExited;
        if(state==null || ring==null)return;
        state.Text=stopping?"ОТКЛЮЧЕНИЕ…":ready?"ПОДКЛЮЧЕНО":running?"ПОДКЛЮЧЕНИЕ…":"ОТКЛЮЧЕНО";
        hint.Text=running?(ready?"Соединение установлено":"Ожидаем ответ сервера"):(stopReason!=""?stopReason:"Нажмите на круг, чтобы подключить VPN");
        ring.Stroke=running?orange:new SolidColorBrush(Color.FromRgb(69,66,73));power.Foreground=running?orange:muted;
        ring.Effect=running?new DropShadowEffect{Color=Colors.OrangeRed,BlurRadius=ready?30:15,ShadowDepth=0,Opacity=.85}:null;
        power.IsEnabled=!stopping;
    }
    void ShowSettings() {
        var p=Page("Настройки");var card=new StackPanel();card.Children.Add(Text("Ссылка подключения",18));
        link=new PasswordBox{Password=saved.link,Margin=new Thickness(0,14,0,6)};shownLink=new TextBox{Text=saved.link,TextWrapping=TextWrapping.Wrap,MaxHeight=125,Visibility=Visibility.Collapsed,Margin=new Thickness(0,14,0,6)};
        card.Children.Add(link);card.Children.Add(shownLink);
        var reveal=Btn("Показать ссылку",()=>{if(shownLink.Visibility==Visibility.Collapsed){shownLink.Text=link.Password;shownLink.Visibility=Visibility.Visible;link.Visibility=Visibility.Collapsed;}else{link.Password=shownLink.Text;link.Visibility=Visibility.Visible;shownLink.Visibility=Visibility.Collapsed;}},false);card.Children.Add(reveal);
        card.Children.Add(Btn("Вставить из буфера",()=>{try {string s=Clipboard.GetText().Trim();link.Password=s;shownLink.Text=s;}catch{saveHint.Text="Не удалось прочитать буфер обмена.";}},false));
        card.Children.Add(Btn("Сохранить ссылку",()=>{try {if(core!=null&&!core.HasExited)throw new Exception("Сначала отключите VPN.");string s=shownLink.Visibility==Visibility.Visible?shownLink.Text:link.Password;Profile.Parse(s);saved.link=s.Trim();Storage.Save(saved);saveHint.Text="Ссылка сохранена";RefreshSubscription(false);}catch(Exception e){saveHint.Text=e.Message;}},true));
        saveHint=Text(saved.link==""?"":"Ссылка сохранена",12);saveHint.Foreground=muted;card.Children.Add(saveHint);p.Children.Add(Card(card));
        var sub=new StackPanel();sub.Children.Add(Text("Подписка",18));subscription=Text("Нажмите «Обновить»",18);subscription.Foreground=orange;subscription.Margin=new Thickness(0,12,0,10);sub.Children.Add(subscription);
        sub.Children.Add(Btn("Обновить",async()=>await RefreshSubscription(true),false));sub.Children.Add(Btn("Продлить подписку",()=>OpenUrl("https://2.56.174.146/renew"),false));p.Children.Add(Card(sub));
        var workerPanel=new StackPanel();var label=Text("Параллельные потоки: "+saved.workers,17);workerPanel.Children.Add(label);workers=new Slider{Minimum=3,Maximum=27,TickFrequency=3,IsSnapToTickEnabled=true,Value=saved.workers,Margin=new Thickness(0,18,0,10),IsEnabled=core==null||core.HasExited};workers.ValueChanged+=(s,e)=>{saved.workers=(int)workers.Value;label.Text="Параллельные потоки: "+saved.workers;try{Storage.Save(saved);}catch{}};workerPanel.Children.Add(workers);workerPanel.Children.Add(Text("Применяется при следующем подключении",12));p.Children.Add(Card(workerPanel));
        p.Children.Add(Btn("Журнал VPN",()=>ShowLog(),false));p.Children.Add(Btn("Поддержка",()=>ShowChat(),true));p.Children.Add(Btn("Восстановить сеть",async()=>await Repair(),false));var id=Text("ID компьютера: "+saved.id+"\nOpenFlux 1.0.1 · Windows x64",11);id.Foreground=muted;id.Margin=new Thickness(0,18,0,4);p.Children.Add(id);
        if(!preview)RefreshSubscription(false);
    }
    async Task Connect() {
        try {
            current=Profile.Parse(saved.link);
            string path=System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"openflux-core.exe");
            if(!File.Exists(path))throw new Exception("Распакуйте весь архив OpenFlux: рядом с приложением должно быть сетевое ядро.");
            ready=false;stopping=false;stopReason="";logs.Clear();lastLog="";started=DateTime.UtcNow;int run=++generation;
            var ps=new ProcessStartInfo(path){UseShellExecute=false,CreateNoWindow=true,RedirectStandardInput=true,RedirectStandardOutput=true,RedirectStandardError=true,StandardOutputEncoding=Encoding.UTF8,StandardErrorEncoding=Encoding.UTF8,WorkingDirectory=AppDomain.CurrentDomain.BaseDirectory};
            core=new Process{StartInfo=ps,EnableRaisingEvents=true};var child=core;
            child.OutputDataReceived+=(s,e)=>{if(e.Data!=null)Dispatcher.BeginInvoke(new Action(()=>{if(run==generation)HandleLine(e.Data);}));};
            child.ErrorDataReceived+=(s,e)=>{if(e.Data!=null)Dispatcher.BeginInvoke(new Action(()=>{if(run==generation)HandleLine(e.Data);}));};
            child.Exited+=(s,e)=>Task.Run(()=>{child.WaitForExit();Dispatcher.BeginInvoke(new Action(()=>{
                if(run!=generation)return;ready=false;stopping=false;if(captcha!=null)captcha.Close();
                if(stopReason=="")stopReason="Сетевое ядро завершилось (код "+child.ExitCode+"). Причина — в журнале.";
                AddLog("VPN остановлен. Причина: "+stopReason);SaveLastLog();PaintState();if(closeAfter)Close();
            }));});
            child.Start();child.BeginOutputReadLine();child.BeginErrorReadLine();child.StandardInput.WriteLine(current.Config(saved.id,saved.workers));child.StandardInput.Flush();PaintState();AddLog("Начато подключение к "+current.host);RefreshSubscription(false);
            var budget=new StartupBudget();
            while(run==generation && !ready && !child.HasExited && !stopping) {
                await Task.Delay(1000);
                if(run!=generation || child.HasExited || stopping)break;
                if(budget.Tick(captchaBusy,ready)){await Stop("Сервер не подтвердил настройку VPN за 3 минуты (время проверки VK не учитывается).");break;}
            }
        } catch(Exception e) {AddLog(e.Message);MessageBox.Show(e.Message,"OpenFlux",MessageBoxButton.OK,MessageBoxImage.Information);PaintState();}
    }
    async Task Stop(string reason="Отключено пользователем") {
        if(core==null||core.HasExited||stopping)return;stopReason=Redaction.Clean(reason,current);AddLog("Причина остановки: "+stopReason);stopping=true;PaintState();if(captcha!=null)captcha.Close();
        var child=core;try{child.StandardInput.WriteLine("STOP");child.StandardInput.Flush();child.StandardInput.Close();}catch{}
        // Wait for route/DNS cleanup rather than killing the network process.
        for(int i=0;i<120 && !child.HasExited;i++)await Task.Delay(250);
        if(!child.HasExited){AddLog("Отключение ещё выполняется. Ожидаем восстановления сети.");if(hint!=null)hint.Text="Восстанавливаем обычное подключение…";}
    }
    async Task Repair() {
        if(core!=null&&!core.HasExited){MessageBox.Show("Сначала отключите VPN.","OpenFlux");return;}
        try{var p=Process.Start(new ProcessStartInfo(System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"openflux-core.exe"),"--repair"){UseShellExecute=false,CreateNoWindow=true});await Task.Run(()=>p.WaitForExit());MessageBox.Show(p.ExitCode==0?"Настройки сети OpenFlux очищены.":"Не удалось завершить восстановление сети.","OpenFlux");p.Dispose();}catch{MessageBox.Show("Не удалось запустить восстановление.","OpenFlux");}
    }
    void HandleLine(string line) {
        if(line.StartsWith("CAPTCHA_SOLVE|")){ShowCaptcha(line);return;}
        if(line.StartsWith("__CSQTT_EVENT__|")) {
            var parts=line.Split(new[]{'|'},3);if(parts.Length<3)return;
            try{var v=json.Deserialize<Dictionary<string,object>>(parts[2]);
                if(parts[1]=="TUNNEL_READY") {ready=true;PaintState();}
                if(parts[1]=="STATS") {if(traffic!=null)traffic.Text="Потоки: "+v["active"]+"  ·  Трафик: "+((Convert.ToDouble(v["bytes_up"])+Convert.ToDouble(v["bytes_down"]))/1048576).ToString("0.0")+" МБ";}
                if(parts[1]=="ERROR"){string code=Convert.ToString(v["code"]);AddLog("Ошибка: "+Convert.ToString(v["message"]));if(v.ContainsKey("fatal")&&Convert.ToBoolean(v["fatal"]))Stop(Convert.ToString(v["message"]));}
            }catch{}return;
        }
        // TUNNEL_READY confirms configuration independently of diagnostic wording.
        if(line.Contains("Настройка TUN не удалась")){ready=false;Stop(line);}
        AddLog(line);
    }
    void AddLog(string s) {
        s=Redaction.Clean(s,current).Trim();if(s=="")return;
        if(s==lastLog&&logs.Count>0){repetitions++;logs[logs.Count-1]=lastLogTime+"  "+s+" (x"+repetitions+")";}
        else{lastLog=s;lastLogTime=DateTime.Now.ToString("HH:mm:ss");repetitions=1;logs.Add(lastLogTime+"  "+s);}
        while(logs.Count>2000)logs.RemoveAt(0);logDirty=true;
    }
    void SaveLastLog(){if(preview)return;try{Directory.CreateDirectory(Storage.Dir);File.WriteAllLines(System.IO.Path.Combine(Storage.Dir,"last-session.log"),logs,Encoding.UTF8);}catch{}}
    void ExportLog(){var dlg=new Microsoft.Win32.SaveFileDialog{FileName="OpenFlux-журнал.txt",Filter="Текстовый журнал|*.txt"};if(dlg.ShowDialog(this)==true)try{File.WriteAllLines(dlg.FileName,logs,Encoding.UTF8);}catch{MessageBox.Show("Не удалось сохранить файл.","OpenFlux");}}

    void ShowLog() {var p=Page("Журнал VPN");logBox=new TextBox{Text=String.Join(Environment.NewLine,logs),IsReadOnly=true,TextWrapping=TextWrapping.Wrap,VerticalScrollBarVisibility=ScrollBarVisibility.Auto,Height=420,FontFamily=new FontFamily("Consolas"),FontSize=12,Margin=new Thickness(0,18,0,10)};p.Children.Add(logBox);p.Children.Add(Btn("Копировать журнал",()=>{try{Clipboard.SetText(String.Join(Environment.NewLine,logs));}catch{}},false));p.Children.Add(Btn("Сохранить журнал в файл",()=>ExportLog(),true));p.Children.Add(Btn("Очистить",()=>{logs.Clear();lastLog="";logBox.Clear();SaveLastLog();},false));}
    async Task<Dictionary<string,object>> Api(string route,string body=null) {
        var p=Profile.Parse(saved.link);if(!p.Panel)throw new Exception("Этот сервер не поддерживает панель OpenFlux.");
        using(var client=new HttpClient(new HttpClientHandler{AllowAutoRedirect=false})) {
            client.Timeout=TimeSpan.FromSeconds(8);client.DefaultRequestHeaders.Authorization=new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer",p.password);
            HttpResponseMessage r=body==null?await client.GetAsync("https://2.56.174.146/api/client/"+route):await client.PostAsync("https://2.56.174.146/api/client/"+route,new StringContent(body,Encoding.UTF8,"application/json"));
            r.EnsureSuccessStatusCode();return json.Deserialize<Dictionary<string,object>>(await r.Content.ReadAsStringAsync());
        }
    }
    async Task RefreshSubscription(bool explicitRequest) {
        if(preview||apiBusy||saved.link=="")return;apiBusy=true;
        try {var v=await Api("subscription");string status=Convert.ToString(v["state"]),caption;
            if(status=="expired")caption="Подписка закончилась";
            else if(v["expires_at"]==null)caption="Без ограничения срока";
            else {double days=Math.Ceiling((Convert.ToDouble(v["expires_at"])-Convert.ToDouble(v["server_time"]))/86400);caption="Осталось дней: "+Math.Max(0,days);}
            if(subscription!=null)subscription.Text=caption;
            if(status=="expired" && core!=null&&!core.HasExited){await Stop("Подписка закончилась");if(MessageBox.Show("Подписка закончилась. Открыть страницу продления?","OpenFlux",MessageBoxButton.YesNo)==MessageBoxResult.Yes)OpenUrl("https://2.56.174.146/renew");}
        }catch{if(subscription!=null)subscription.Text="Не удалось получить срок";if(explicitRequest)AddLog("Срок подписки временно недоступен. Это не мешает запуску VPN.");}finally{apiBusy=false;}
    }
    void ShowChat() {
        content.Children.Clear();subscription=null;logBox=null;var g=new Grid();g.RowDefinitions.Add(new RowDefinition{Height=GridLength.Auto});g.RowDefinitions.Add(new RowDefinition());g.RowDefinitions.Add(new RowDefinition{Height=GridLength.Auto});
        var top=new StackPanel();top.Children.Add(Btn("←  Назад",()=>ShowSettings(),false));top.Children.Add(Text("Поддержка",28));chatHint=Text("",12);chatHint.Foreground=muted;top.Children.Add(chatHint);g.Children.Add(top);
        chatMessages=new StackPanel();var scroll=new ScrollViewer{Content=chatMessages,VerticalScrollBarVisibility=ScrollBarVisibility.Auto,Margin=new Thickness(0,12,0,12)};Grid.SetRow(scroll,1);g.Children.Add(scroll);
        var bottom=new StackPanel();chatText=new TextBox{AcceptsReturn=true,TextWrapping=TextWrapping.Wrap,MinHeight=65,MaxHeight=130,MaxLength=500};bottom.Children.Add(chatText);var send=Btn("Отправить",()=>{},true);send.Click+=async(s,e)=>{string body=chatText.Text.Trim();if(body=="")return;send.IsEnabled=false;chatHint.Text="Отправляем…";try{await Api("conversation",json.Serialize(new{body=body,nonce=Guid.NewGuid().ToString()}));chatText.Clear();chatHint.Text="Сообщение отправлено";await LoadChat();}catch{chatHint.Text="Не удалось отправить. Проверьте интернет и повторите.";}finally{send.IsEnabled=true;}};bottom.Children.Add(send);Grid.SetRow(bottom,2);g.Children.Add(bottom);content.Children.Add(g);if(!preview)LoadChat();
    }
    async Task LoadChat() {
        var target=chatMessages;if(target==null)return;
        try{var v=await Api("conversation");if(target!=chatMessages)return;target.Children.Clear();var messages=(System.Collections.IEnumerable)v["messages"];
            foreach(Dictionary<string,object> m in messages){var panel=new StackPanel();var label=Text(Convert.ToString(m["sender"])=="client"?"Вы":"Поддержка OpenFlux",12);label.Foreground=orange;panel.Children.Add(label);string body=Convert.ToString(m["body"]);var block=Text("",14);int pos=0;foreach(Match match in Regex.Matches(body,@"https://[^\s<>]+")){block.Inlines.Add(body.Substring(pos,match.Index-pos));string url=match.Value;var a=new Hyperlink(new Run(url)){Foreground=orange};a.Click+=(s,e)=>OpenUrl(url);block.Inlines.Add(a);pos=match.Index+match.Length;}block.Inlines.Add(body.Substring(pos));panel.Children.Add(block);target.Children.Add(Card(panel));}
            if(target.Children.Count==0)target.Children.Add(Text("Напишите нам — поможем с подключением."));
        }catch{if(target==chatMessages)chatHint.Text="Переписка недоступна. Проверьте интернет и ссылку.";}
    }
    async Task Notices() {
        if(noticesBusy||tray==null)return;noticesBusy=true;
        try{var v=await Api("messages");foreach(Dictionary<string,object> m in (System.Collections.IEnumerable)v["messages"]){if(!ready)break;int id=Convert.ToInt32(m["id"]);string body=Convert.ToString(m["body"]);if(noticesShown.Add(id))tray.ShowBalloonTip(10000,"Сообщение OpenFlux",body,System.Windows.Forms.ToolTipIcon.Info);await Api("messages/"+id+"/seen","{}");break;}}catch{}finally{noticesBusy=false;}
    }
    async void ShowCaptcha(string line) {
        if(captchaBusy){SendControl("CAPTCHA_RESULT|error:busy");return;}
        var parts=line.Split('|');Uri url;
        if(parts.Length<3||!Uri.TryCreate(parts[2],UriKind.Absolute,out url)||url.Scheme!="https"||!VkHost(url.Host)){SendControl("CAPTCHA_RESULT|error:url");return;}
        captchaBusy=true;AddLog("VK запросил проверку. Выполните её в открывшемся окне.");
        var w=new Window{Title="OpenFlux · Проверка VK",Owner=this,Width=460,Height=680,WindowStartupLocation=WindowStartupLocation.CenterOwner};captcha=w;
        var web=new WebView2();w.Content=web;bool done=false;
        Action<string> finish=result=>{if(done)return;done=true;SendControl("CAPTCHA_RESULT|"+result);w.Close();};
        w.Closed+=(s,e)=>{if(!done){done=true;SendControl("CAPTCHA_RESULT|error:closed");}web.Dispose();captcha=null;captchaBusy=false;};
        try {
            w.Show();var env=await CoreWebView2Environment.CreateAsync(null,System.IO.Path.Combine(Storage.Dir,"WebView"));await web.EnsureCoreWebView2Async(env);
            web.CoreWebView2.Settings.AreDevToolsEnabled=false;
            web.CoreWebView2.NewWindowRequested+=(s,e)=>{e.Handled=true;};
            web.CoreWebView2.WebResourceResponseReceived+=async(s,e)=>{try{Uri request;if(!Uri.TryCreate(e.Request.Uri,UriKind.Absolute,out request)||!VkHost(request.Host))return;using(var stream=await e.Response.GetContentAsync())using(var reader=new StreamReader(stream)){string text=await reader.ReadToEndAsync();var match=Regex.Match(text,"\"success_token\"\\s*:\\s*\"([a-zA-Z0-9_-]+)\"");if(match.Success)finish(match.Groups[1].Value);}}catch{}};
            web.Source=url;await Task.Delay(115000);if(!done)finish("error:timeout");
        }catch{AddLog("Не удалось открыть проверку VK. Установите Microsoft Edge WebView2 Runtime.");if(!done)finish("error:webview");}
    }
    static bool VkHost(string h){return new[]{"vk.com","vk.ru","vk.me","vkuser.net"}.Any(d=>h==d||h.EndsWith("."+d,StringComparison.OrdinalIgnoreCase));}
    void SendControl(string command){try{if(core!=null&&!core.HasExited){core.StandardInput.WriteLine(command);core.StandardInput.Flush();}}catch{}}
    static void OpenUrl(string url){Uri u;if(Uri.TryCreate(url,UriKind.Absolute,out u)&&u.Scheme=="https")try{Process.Start(new ProcessStartInfo(url){UseShellExecute=true});}catch{MessageBox.Show("Не удалось открыть браузер.","OpenFlux");}}
    public void Preview(string page,string output) {if(page=="settings")ShowSettings();else if(page=="support")ShowChat();else ShowHome();var view=(FrameworkElement)Content;view.Measure(new Size(540,760));view.Arrange(new Rect(0,0,540,760));view.UpdateLayout();var drawing=new DrawingVisual();using(var dc=drawing.RenderOpen()){dc.DrawRectangle(bg,null,new Rect(0,0,540,760));}var bmp=new RenderTargetBitmap(540,760,96,96,PixelFormats.Pbgra32);bmp.Render(drawing);bmp.Render(view);var png=new PngBitmapEncoder();png.Frames.Add(BitmapFrame.Create(bmp));using(var f=File.Create(output))png.Save(f);}
}
public static class Program {
    [STAThread] public static void Main(string[] args) {
        ServicePointManager.SecurityProtocol=SecurityProtocolType.Tls12;
        bool preview=args.Length>=3&&args[0]=="--preview";
        bool owns;using(var single=new Mutex(true,"Local\\OpenFlux.Windows",out owns)) {
            if(!owns&&!preview){MessageBox.Show("OpenFlux уже запущен. Откройте окно через значок возле часов.","OpenFlux");return;}
            var app=new Application();app.DispatcherUnhandledException+=(s,e)=>{MessageBox.Show("Не удалось выполнить действие. Перезапустите OpenFlux.","OpenFlux");e.Handled=true;};
            var window=new MainWindow(preview);if(preview)window.Preview(args[1],args[2]);else app.Run(window);
        }
    }
}
}
