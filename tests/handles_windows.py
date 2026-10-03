"""Lectores Windows para las medidas de herencia de fixtures propias."""
import sys, os, ctypes as C, ctypes.wintypes as W, socket, time, subprocess, json
K=C.WinDLL('kernel32',use_last_error=True); N=C.WinDLL('ntdll')
K.OpenProcess.argtypes=[W.DWORD,W.BOOL,W.DWORD]; K.OpenProcess.restype=W.HANDLE
K.CloseHandle.argtypes=[W.HANDLE]; K.GetCurrentProcess.restype=W.HANDLE
K.DuplicateHandle.argtypes=[W.HANDLE,W.HANDLE,W.HANDLE,C.POINTER(W.HANDLE),W.DWORD,W.BOOL,W.DWORD]
N.NtQueryInformationProcess.argtypes=[W.HANDLE,W.ULONG,C.c_void_p,W.ULONG,C.POINTER(W.ULONG)]
K.TerminateProcess.argtypes=[W.HANDLE,W.UINT]
N.NtQueryObject.argtypes=[W.HANDLE,W.ULONG,C.c_void_p,W.ULONG,C.POINTER(W.ULONG)]
WS=C.WinDLL('ws2_32')
WS.getsockname.argtypes=[C.c_size_t,C.c_void_p,C.POINTER(C.c_int)]
WS.getsockopt.argtypes=[C.c_size_t,C.c_int,C.c_int,C.c_void_p,C.POINTER(C.c_int)]
class US(C.Structure):
    _fields_=[('length',W.USHORT),('max',W.USHORT),('buffer',C.c_void_p)]
class Entry(C.Structure):
    _fields_=[('value',C.c_size_t),('count',C.c_size_t),('ptrs',C.c_size_t),('access',W.DWORD),('type',W.DWORD),('attrs',W.DWORD),('reserved',W.DWORD)]
def sockets(pid):
    h=K.OpenProcess(0x440,False,pid)
    if not h: raise C.WinError(C.get_last_error())
    try:
        b=C.create_string_buffer(1024*1024); needed=W.ULONG()
        st=N.NtQueryInformationProcess(h,51,b,len(b),C.byref(needed))
        if st: raise RuntimeError('handle snapshot status=%08x'%(st & 0xffffffff))
        count=C.c_size_t.from_buffer(b).value
        assert 16+count*C.sizeof(Entry)<=len(b)
        result=[]
        for i in range(count):
            e=Entry.from_buffer(b,16+i*C.sizeof(Entry))
            if e.attrs & 2:
                row={'handle':e.value,'attrs':e.attrs,'type':e.type,'access':hex(e.access)}
                if e.access == 0x16019f:
                    dup=W.HANDLE()
                    assert K.DuplicateHandle(h,e.value,K.GetCurrentProcess(),C.byref(dup),0,False,2)
                    try:
                        nb=C.create_string_buffer(4096); nr=W.ULONG()
                        qs=N.NtQueryObject(dup,1,nb,len(nb),C.byref(nr))
                        if qs == 0:
                            u=US.from_buffer(nb);row['name']=C.wstring_at(u.buffer,u.length//2) if u.buffer else ''
                        addr=C.create_string_buffer(128); al=C.c_int(128)
                        if WS.getsockname(dup.value,addr,C.byref(al))==0:
                            row['socket_port']=int.from_bytes(addr.raw[2:4],'big')
                            row['socket_addr']=socket.inet_ntoa(addr.raw[4:8])
                    finally:K.CloseHandle(dup)
                result.append(row)
        return {'pid':pid,'handle_count':count,'inheritable':result}
    finally:K.CloseHandle(h)
def bind_result(port):
    with socket.socket() as s:
        s.setsockopt(socket.SOL_SOCKET,socket.SO_EXCLUSIVEADDRUSE,1)
        try:s.bind(('127.0.0.1',port));return 'FREE'
        except OSError as e:return 'BUSY winerror=%s'%e.winerror

class ProcessEntry(C.Structure):
    _fields_=[('size',W.DWORD),('usage',W.DWORD),('pid',W.DWORD),
              ('heap',C.c_size_t),('module',W.DWORD),('threads',W.DWORD),
              ('parent',W.DWORD),('priority',W.LONG),('flags',W.DWORD),
              ('exe',W.WCHAR*260)]
K.CreateToolhelp32Snapshot.argtypes=[W.DWORD,W.DWORD]
K.CreateToolhelp32Snapshot.restype=W.HANDLE
K.Process32FirstW.argtypes=[W.HANDLE,C.POINTER(ProcessEntry)]
K.Process32NextW.argtypes=[W.HANDLE,C.POINTER(ProcessEntry)]
def children(parent, name):
    h=K.CreateToolhelp32Snapshot(2,0)
    if h == C.c_void_p(-1).value: raise C.WinError(C.get_last_error())
    try:
        e=ProcessEntry();e.size=C.sizeof(e);rows=[]
        ok=K.Process32FirstW(h,C.byref(e))
        while ok:
            rows.append((e.pid,e.parent,e.exe))
            ok=K.Process32NextW(h,C.byref(e))
        owned={parent}
        for unused in range(len(rows)):
            added={pid for pid,ppid,exe in rows if ppid in owned}-owned
            if not added:break
            owned.update(added)
        return [pid for pid,ppid,exe in rows if pid in owned and pid!=parent and exe.lower()==name.lower()]
    finally:K.CloseHandle(h)

def event_in(pid, name):
    h=K.OpenProcess(0x440,False,pid)
    if not h:raise C.WinError(C.get_last_error())
    try:
        b=C.create_string_buffer(1024*1024);needed=W.ULONG()
        st=N.NtQueryInformationProcess(h,51,b,len(b),C.byref(needed))
        if st:raise RuntimeError('handle snapshot status=%08x'%(st&0xffffffff))
        count=C.c_size_t.from_buffer(b).value
        assert 16+count*C.sizeof(Entry)<=len(b)
        for i in range(count):
            e=Entry.from_buffer(b,16+i*C.sizeof(Entry))
            if e.access!=0x1f0003:continue # evento creado con EVENT_ALL_ACCESS
            dup=W.HANDLE()
            if not K.DuplicateHandle(h,e.value,K.GetCurrentProcess(),C.byref(dup),0,False,2):continue
            try:
                nb=C.create_string_buffer(4096);nr=W.ULONG()
                if N.NtQueryObject(dup,1,nb,len(nb),C.byref(nr))==0:
                    u=US.from_buffer(nb)
                    text=C.wstring_at(u.buffer,u.length//2) if u.buffer else ''
                    if text.endswith('\\'+name):return True
            finally:K.CloseHandle(dup)
        return False
    finally:K.CloseHandle(h)
