# .swarm/references

Imagens de referência visual para a etapa de design.

## Como usar
- Coloque aqui prints, mockups, capturas de apps que você gosta, logotipo, paleta etc. (PNG, JPG, WebP).
- Organize por tela ou assunto se quiser: `.swarm/references/login/`, `.swarm/references/marca/`.
- Nomes descritivos ajudam: `dashboard-desktop.png`, `checkout-mobile.png`.
- O `designer` lê tudo que está aqui antes de propor um layout. Se uma tarefa de frontend precisar de uma referência que não existe, o swarm pergunta quais telas você quer adicionar.

Esta pasta é **sua**: adicione, organize e remova o que quiser, a qualquer momento. O swarm só cria arquivos novos aqui (as capturas, em `capturas/`) e nunca apaga, renomeia ou sobrescreve os seus.

## Se você não trouxer referências
Se você não indicar nada, o swarm pesquisa inspirações em plataformas como o Dribbble, propõe até 3 direções com links e pergunta qual seguir. A direção escolhida fica em `inspiracoes.md` (só links e notas: as imagens dessas plataformas não são baixadas nem versionadas). Se você não quiser essa pesquisa, diga "sem referências" ou "não pesquise".

## Capturas automáticas (só telas públicas)
Quando a aplicação já existe, o swarm tira prints das telas **públicas** e salva em `.swarm/references/capturas/<tela>-<viewport>.png` (script `capture-screens.sh` do plugin; só localhost por padrão). Ele nunca faz login nem usa cookie, token ou sessão: telas que exigem login ficam por sua conta, adicione as imagens você mesmo.

## Imagens coladas no chat
O Claude consegue **ver** uma imagem colada na conversa, mas ela não vira arquivo: subagentes não a enxergam e ela não chega ao Claude Design. Salve o arquivo original nesta pasta (ou diga o caminho dele). Para imagens coladas o swarm também registra uma descrição em `.md` aqui.

## Versionamento e dados sensíveis
Esta pasta é **versionada** junto com o `.swarm/`. Por isso, antes de comitar qualquer imagem nova o swarm pede que você confirme que ela **não contém dados sensíveis** (dados de clientes reais, e-mails, telefones, documentos, tokens, chaves, URLs internas, informações financeiras ou confidenciais). Sem a sua confirmação, a imagem não é comitada. Capturas de uma aplicação com dados reais são o caso mais comum de vazamento: confira.
