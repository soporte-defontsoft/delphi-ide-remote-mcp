# -*- coding: utf-8 -*-
"""MANUAL: FMX en diseno frente al control en ejecucion, WAV y HTTP propios.
RENDER_FMX_MEASURE_HELPER: copia con URenderFmxReachDummy.
RENDER_FMX_RUNTIME_HELPER: misma copia con PonEnDiseno(False), solo como control.
El producto conserva PonEnDiseno(True). No instala reglas de red.
"""
import atexit,http.server,json,os,shutil,threading,urllib.request,wave
import mcp_cliente as mc
HELPERS=[('design',os.environ.get('RENDER_FMX_MEASURE_HELPER','')),
         ('runtime',os.environ.get('RENDER_FMX_RUNTIME_HELPER',''))]
if not all(p for _,p in HELPERS):
    mc.fin('render FMX diseno 118',sin_checks='manual: faltan los dos ayudantes FMX DUMMY de medida')
BASE=mc.carpeta('render-fmx-diseno-118');atexit.register(mc.borra,BASE)
JAIL=os.path.join(BASE,'jail');os.makedirs(JAIL)
hits=[]
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        hits.append(self.path);body=b'<html><body>DUMMY</body></html>'
        self.send_response(200);self.send_header('Content-Type','text/html')
        self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
    def log_message(self,*args):pass
http=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
threading.Thread(target=http.serve_forever,daemon=True).start()
url='http://127.0.0.1:%d/DUMMY'%http.server_port
wav=os.path.join(JAIL,'DUMMY.wav')
with wave.open(wav,'wb') as file:
    file.setnchannels(1);file.setsampwidth(2);file.setframerate(8000);file.writeframes(b'\x00\x00'*8000)
form=os.path.join(JAIL,'DUMMY-media-web.fmx')
with open(form,'w',encoding='ascii') as file:
    file.write("object Dummy: TDummy\n ClientWidth = 160\n ClientHeight = 100\n"+
      " object Player1: TMediaPlayer\n FileName = '"+wav+"'\n end\n"+
      " object Web1: TWebBrowser\n URL = '"+url+"'\n end\n"+
      " object Measure: TDummyFmxMeasure\n end\nend\n")
try:
    urllib.request.urlopen(url+'/control',timeout=2).read()
    mc.check('control endpoint HTTP propio',bool(hits))
    for mode,helper in HELPERS:
        hits.clear()
        for d,_,ns in os.walk(BASE):
            if 'DUMMY-media.txt' in ns:os.remove(os.path.join(d,'DUMMY-media.txt'))
        exe=mc.copia_exe(os.path.join(BASE,mode),con_render=True,con_conversor=True)
        shutil.copyfile(helper,os.path.join(os.path.dirname(exe),'DelphiFormRenderFmx.exe'))
        srv=mc.Stdio(exe,mc.entorno({'DELPHI_MCP_ROOTS':JAIL}),nombre='fmx-'+mode,t=110)
        try:
            out=srv.call('delphi_designer',dict(command='preview',path=form,out=os.path.join(JAIL,mode+'.png'),inline='false'))
            try:r=json.loads(out)
            except:r={}
            marker=[mc.lee(os.path.join(d,'DUMMY-media.txt')) for d,_,ns in os.walk(BASE) if 'DUMMY-media.txt' in ns]
            mc.check(mode+' dibuja FMX sin ignorar propiedades',r.get('framework')=='fmx' and not r.get('ignored'),out[:350])
            mc.check(mode+' media activada solo en ejecucion',
              marker==(['False:0'] if mode=='design' else ['True:10000000']),marker)
            mc.check(mode+' navega solo en ejecucion',bool(hits)==(mode=='runtime'),hits)
            mc.check(mode+' servidor vivo',not mc.fallo(srv.call('delphi_list',{'root':JAIL})))
        finally:srv.cierra()
finally:
    http.shutdown();http.server_close();mc.borra(BASE)
mc.check('BASE borrada con los exes',not os.path.exists(BASE))
mc.fin('render FMX diseno 118')
