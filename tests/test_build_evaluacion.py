"""Contrato de evaluacion: solo ficheros propios del arnes, sin Exec.
Una propiedad intenta leer un testigo externo; MSBuild intenta cargar otro
proyecto que solo tiene Message. Ninguna fixture lanza programas ajenos.
"""
import os
from xml.sax.saxutils import escape
import mcp_cliente as mc
BASE=mc.carpeta('build-evaluacion');JAIL=os.path.join(BASE,'jail');OTHER=os.path.join(BASE,'testigos')
os.makedirs(JAIL);os.makedirs(OTHER)
EXE=mc.copia_exe(os.path.join(BASE,'srv'))
srv=mc.Stdio(EXE,mc.entorno({'DELPHI_MCP_ROOTS':JAIL}),nombre='evaluacion',t=600)
try:
    project=os.path.join(JAIL,'Fixture')
    r=srv.call('delphi_create',{'kind':'project-console','name':'Fixture','dir':project})
    mc.check('fixture creada',mc.abre(r,'SK_CREATE_CREADO_PROYECTO_FMT'),r[:200])
    path=os.path.join(project,'Fixture.dproj')
    with open(path,encoding='utf-8-sig') as f:normal=f.read()
    marker='CONTRATO_EVALUACION_EXTERNO'
    witness=os.path.join(OTHER,'testigo.txt')
    with open(witness,'w') as f:f.write(marker)
    nested=os.path.join(OTHER,'fixture.proj')
    with open(nested,'w') as f:f.write('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003"><Target Name="Fixture"><Message Text="'+marker+'" Importance="High"/></Target></Project>')
    cases=(
        ('propiedad-nbsp', '<PropertyGroup><Fixture>$('+chr(160)+'[System.IO.File]::ReadAllText(\''+escape(witness)+'\'))</Fixture></PropertyGroup><Target Name="Fixture" BeforeTargets="Build"><Message Text="$(Fixture)" Importance="High"/></Target>'),
        ('propiedad-thinspace', '<PropertyGroup><Fixture>$('+chr(0x2009)+'[System.IO.File]::ReadAllText(\''+escape(witness)+'\'))</Fixture></PropertyGroup><Target Name="Fixture" BeforeTargets="Build"><Message Text="$(Fixture)" Importance="High"/></Target>'),
        ('propiedad', '<PropertyGroup><Fixture>$([System.IO.File]::ReadAllText(\''+escape(witness)+'\'))</Fixture></PropertyGroup><Target Name="Fixture" BeforeTargets="Build"><Message Text="$(Fixture)" Importance="High"/></Target>'),
        ('msbuild', '<Target Name="Fixture" BeforeTargets="Build"><MSBuild Projects="'+escape(nested)+'" Targets="Fixture"/></Target>'),
        ('readlinesfromfile', '<Target Name="Fixture" BeforeTargets="Build"><ReadLinesFromFile File="'+escape(witness)+'"><Output TaskParameter="Lines" ItemName="FixtureLines"/></ReadLinesFromFile><Message Text="@(FixtureLines)" Importance="High"/></Target>'),


        ('propiedad-entidad', '<PropertyGroup><Fixture>&#36;([System.IO.File]::ReadAllText(\''+escape(witness)+'\'))</Fixture></PropertyGroup><Target Name="Fixture" BeforeTargets="Build"><Message Text="$(Fixture)" Importance="High"/></Target>'),
        ('propiedad-espacio', '<PropertyGroup><Fixture>$( [System.IO.File]::ReadAllText(\''+escape(witness)+'\'))</Fixture></PropertyGroup><Target Name="Fixture" BeforeTargets="Build"><Message Text="$(Fixture)" Importance="High"/></Target>'),
    )
    for name,extra in cases:
        with open(path,'w',encoding='utf-8-sig',newline='') as f:f.write(normal.replace('</Project>',extra+'</Project>'))
        r=srv.call('delphi_build',{'project':path,'platform':'Win64','verbosity':'normal'},600)
        mc.check(name+': la puerta rechaza antes de evaluar',mc.rechazado(r) and mc.es(r,'SR_BUILD_HAZARD_FMT'),r[:500])
        mc.check(name+': no lee ni devuelve el testigo',marker not in r,r[-800:])
    with open(path,'w',encoding='utf-8-sig',newline='') as f:f.write(normal)
    r=srv.call('delphi_build',{'project':path,'platform':'Win64'},600)
    mc.check('control ordinario compila',mc.como_json(r).get('success') is True,r[:250])
finally:srv.cierra();mc.borra(BASE)
mc.fin('build evaluacion y proyectos anidados')
