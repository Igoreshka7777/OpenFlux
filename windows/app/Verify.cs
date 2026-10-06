using System;
using System.IO;
using System.Windows;
using OpenFlux;
class Verify {
 static int tests;
 static void Check(bool pass,string name){if(!pass)throw new Exception(name);tests++;Console.WriteLine("PASS "+name);}
 static void Reject(string s){try{Profile.Parse(s);}catch{tests++;return;}throw new Exception("Accepted invalid profile");}
 [STAThread] static void Main(string[] args){
  string prefix="csqtt://connect?v=2&host=example.org&peer=46000&password=test-secret";
  var p=Profile.Parse(prefix+"&hashes=abcdefghijklmnop+qrstuvwxyzABCDEF");
  Check(p.hashes=="abcdefghijklmnop,qrstuvwxyzABCDEF","Multiple VK hashes");
  p=Profile.Parse(prefix+"&token=vk1.a.abc%2Bdef");Check(p.token=="vk1.a.abc+def","Token-only link preserves plus");
  Check(Profile.Parse(prefix+"&hashes=https%3A%2F%2Fvk.ru%2Fcall%2Fjoin%2Fabcdefghijklmnop").hashes=="abcdefghijklmnop","VK URL hash");
  Check(Profile.Parse((prefix+"&token=test").Replace("&","&amp;")).port==46000,"HTML-escaped link");
  Reject(prefix);Reject(prefix+"&hashes=");Reject(prefix+"&token=test&host=evil.test");Reject(prefix.Replace("46000","70000")+"&token=test");Reject(prefix.Replace("example.org","bad'host")+"&token=test");Reject(prefix.Replace("v=2","v=1")+"&token=test");
  Check(!p.Panel,"Foreign profile never sends credentials to OpenFlux panel");
  Check(Profile.Parse(prefix.Replace("example.org","2.56.174.146")+"&token=t").Panel,"Main panel profile recognized");
  string clean=Redaction.Clean("error https://vk.ru/api?secret=hide&token=more password=test-secret",p);Check(!clean.Contains("test-secret")&&!clean.Contains("secret=hide"),"Credentials removed from logs");
  string dir=Path.Combine(Path.GetTempPath(),"OpenFlux-test-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(dir);Storage.Dir=dir;Storage.FileName=Path.Combine(dir,"profile.dat");var saved=new Saved{link=prefix+"&token=test"};Storage.Save(saved);var restored=Storage.Load();Check(restored.link==saved.link&&restored.id==saved.id,"Encrypted profile and persistent device ID round trip");Check(!System.Text.Encoding.UTF8.GetString(File.ReadAllBytes(Storage.FileName)).Contains("test-secret"),"Profile stored encrypted");File.Delete(Storage.FileName);Directory.Delete(dir);
  var app=new Application();var w=new MainWindow(true);foreach(string page in new[]{"home","settings","support"}){w.Preview(page,Path.Combine(args[0],"OpenFlux-Windows-"+page+".png"));Check(true,"Rendered "+page);}Console.WriteLine("Verified "+tests+" checks");
 }
}
