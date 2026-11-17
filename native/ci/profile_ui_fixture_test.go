// Disposable loopback fixture for real native profile UI; overlay-only.
package main

import (
 "encoding/json"
 "net"
 "net/http"
 "net/http/httptest"
 "os"
 "strings"
 "sync"
 "testing"
 "time"
)

func TestNativeProfileUIFixture(t *testing.T) {
 if os.Getenv("KM_PROFILE_UI_FIXTURE") != "1" { t.Skip("explicit fixture only") }
 cfg, production, token, second, _ := historyFixture(t)
 session, _ := cfg.auth.store.lookup(token,time.Now())
 owner := session.UserID
 other, _, err := cfg.auth.store.create("profile-other",time.Now()); if err != nil {t.Fatal(err)}
 var mu sync.Mutex
 offline, ownerB := false,false
 requests := []map[string]any{}
 done:=make(chan struct{})
 listener,err:=net.Listen("tcp","127.0.0.1:18880");if err!=nil {t.Fatal(err)}
 server:=&http.Server{ReadHeaderTimeout:5*time.Second}
 server.Handler=http.HandlerFunc(func(w http.ResponseWriter,r *http.Request){
  mu.Lock();defer mu.Unlock()
  respond:=func(v any){w.Header().Set("Content-Type","application/json");json.NewEncoder(w).Encode(v)}
  switch r.URL.Path {
  case "/_fixture/stop":respond(map[string]bool{"ok":true});close(done);return
  case "/_fixture/reset":
   token,_,err=cfg.auth.store.create("owner",time.Now());if err!=nil {t.Error(err)}
   _=os.Remove(cfg.profileLock(owner).path);offline=false;ownerB=false;requests=[]map[string]any{};respond(map[string]string{"owner":owner});return
  case "/_fixture/offline":offline=true;respond(map[string]bool{"ok":true});return
  case "/_fixture/online":offline=false;respond(map[string]bool{"ok":true});return
  case "/_fixture/owner-b":ownerB=true;respond(map[string]bool{"ok":true});return
  case "/_fixture/revoke":
   if err:=cfg.auth.store.revoke(token,time.Now());err!=nil {t.Error(err)};respond(map[string]bool{"ok":true});return
  case "/_fixture/state":respond(map[string]any{"profiles":profileRead(t,production,second),"requests":requests});return
  case "/_fixture/remote-edit", "/_fixture/remote-delete":
   d:=profileRead(t,production,second)
   id:=r.URL.Query().Get("id")
   for _,v:=range d.Items {if !v.Deleted && (id=="" || v.ID==id) {
    method,title,instruction:="PATCH","Remote native title",v.Instruction
    if r.URL.Path=="/_fixture/remote-delete" {method="DELETE";title="";instruction=""}
    result:=authCall(production,method,"/v1/translation-profiles",profileBody("remote-"+time.Now().Format("150405000000000"),v.ID,int(v.Revision),title,instruction),second)
    w.WriteHeader(result.Code);w.Write(result.Body.Bytes());return
   }}
   http.Error(w,"profile missing",404);return
  }
  if r.URL.Path!="/v1/auth/session" && r.URL.Path!="/v1/translation-profiles" {http.Error(w,"inference and unrelated requests forbidden",403);return}
  captured:=r.Header.Get("X-Translation-Owner")
  selected:=token;if ownerB {selected=other};r.Header.Set("Authorization","Bearer "+selected)
  result:=httptest.NewRecorder()
  if offline {result.WriteHeader(503)} else {production.ServeHTTP(result,r)}
  requests=append(requests,map[string]any{"method":r.Method,"path":r.URL.Path,"owner":captured,"status":result.Code})
  for k,vs:=range result.Header(){for _,v:=range vs {w.Header().Add(k,v)}}
  w.WriteHeader(result.Code);w.Write(result.Body.Bytes())
 })
 go server.Serve(listener)
 t.Log("PROFILE_UI_READY 127.0.0.1:18880 synthetic-only")
 select {case <-done:case <-time.After(90*time.Minute):t.Error("fixture deadline")}
 server.Close()
 for _,r:=range requests {if strings.Contains(r["path"].(string),"translations") {t.Error("unexpected inference")}}
}
