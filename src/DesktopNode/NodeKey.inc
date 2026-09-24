{ CLAVE COMPARTIDA servidor <-> nodo (peticion de David, 19-sep-2026).

  El nodo de escritorio es un programa suelto que vive en el disco: al lado
  del servidor en Windows, y dentro del area de PAServer en cada Linux
  aprovisionado. Con esta clave, ejecutarlo a mano NO HACE NADA: solo
  obedece cuando quien lo llama es el servidor MCP, que se la pasa en el
  primer argumento.

  Que NO es: un secreto de verdad. El nodo corre con el mismo usuario que
  quien podria ejecutarlo, y la clave viaja dentro del binario: quien lo
  tenga puede sacarla. Es un pestillo, no una cerradura - frena el uso
  accidental o descuidado (un doble clic, un script que barre binarios),
  no a alguien decidido con acceso a la maquina. Se dice asi en la
  documentacion, sin adornos.

  Este fichero lo incluyen LOS DOS proyectos, para que no puedan
  desincronizarse: McpDesktopNode.dpr y Lsp.RemoteRun.pas del servidor. }

  NODE_KEY = '--mcp=nodo-d7f3a91c4e2b';
