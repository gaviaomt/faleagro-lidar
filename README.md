# FaleAgro LiDAR

Protótipo 1 para medir a **estrutura do dossel da soja** no iPhone 16 Pro Max. O app grava cor e LiDAR e calcula os números no próprio celular. Funciona no talhão **sem internet**.

Não é biomassa, não é peso e não tem calibração de laboratório.

A captura bruta (vídeo, profundidade, confiança, pose e horários) vem do [Stray Scanner](https://github.com/StrayRobots/scanner), licença MIT. O formato bruto continua descrito em [docs/format.md](docs/format.md).

## O que o app mede

Antes de gravar, você preenche: fazenda, talhão, variedade, data de plantio, tratamento, ponto amostral (1 a 5) e a modalidade.

| Modalidade | Como segurar o celular | O que aparece depois |
|---|---|---|
| A · Inferior | Perto do chão, câmera apontando para cima | Abertura do dossel (céu visível) e índice de fechamento |
| B · Lateral 3D | Andar devagar ao redor de cerca de 1 m da linha | Altura média, altura máxima, largura aparente, volume aparente (m³ por metro de linha) e histograma vertical |
| C · Superior | Acima da copa, câmera apontando para baixo | Cobertura de vegetação, solo exposto e altura, se o chão ficar confiável |

Cada número tem uma confiança: alta, média ou baixa. Se o chão não ficar confiável, a altura **não aparece**. O app não inventa esse centímetro.

Durante a gravação a tela avisa: rápido demais, rastreamento perdido ou limitado, profundidade com confiança baixa, área incompleta. A referência de escala, por enquanto, é uma caixinha que você marca. O app não reconhece a referência sozinho.

O histórico fica no celular. Em cada medição dá para exportar um arquivo com `metricas.json`, `nuvem.ply` e a captura bruta.

## O que ele não mede

- Folha por folha, nem haste fina. O LiDAR do iPhone não enxerga isso.
- Biomassa, massa seca, produtividade ou adubo.
- Altura de trena em cada planta. A altura é a superfície aparente da copa.
- O volume aparente inclui o ar entre as folhas. A unidade é metro cúbico por metro de linha. Não é peso.

Sombra forte, sol estourado e céu encoberto mudam cobertura, solo, abertura e fechamento, porque essas contas usam a cor verde junto com a profundidade.

## O que você precisa

- Um Mac.
- O Xcode, de graça na App Store do Mac.
- Um cabo USB-C (o iPhone 16 Pro Max não usa o cabo Lightning antigo).
- O iPhone 16 Pro Max, desbloqueado.
- Um Apple ID gratuito, o mesmo da App Store. Não precisa pagar o programa de desenvolvedor da Apple.
- Internet **no Mac**, uma vez, para baixar o Xcode e a Apple criar o certificado grátis. No campo, o iPhone mede sem Wi-Fi e sem sinal de celular.

## 1. Baixar o projeto

1. No site do GitHub deste repositório, clique no botão verde **Code**.
2. Clique em **Download ZIP**.
3. Abra o arquivo baixado. O Mac cria uma pasta.
4. Não abra a pasta `Pods`, se ela aparecer. Ela não é usada.

## 2. Instalar o Xcode

1. Abra a App Store no Mac.
2. Procure **Xcode** e instale. É grande e demora.
3. Abra o Xcode uma vez. Se ele pedir para instalar componentes extras, aceite e espere terminar.
4. Se pedir para concordar com a licença, aceite.

## 3. Entrar com o Apple ID

1. Com o Xcode aberto, no menu de cima: **Xcode → Settings…** (em alguns Macs o menu diz **Ajustes…** ou **Preferences…**).
2. Aba **Accounts**.
3. Clique no **+** embaixo à esquerda. Escolha **Apple ID**.
4. Entre com o e-mail e a senha. Se a Apple pedir um código, olhe o outro aparelho ou o SMS.
5. Na lista, o time aparece com o seu nome e a palavra **Personal Team**. É isso. Não precisa de conta paga.

## 4. Abrir o projeto

1. Na pasta descompactada, dê dois cliques em **StrayScanner.xcodeproj**. O ícone é azul, com um desenho de martelo.
2. Não abra um arquivo que termine em `.xcworkspace`.
3. Espere a barra de cima parar de girar.
4. Se aparecer um aviso **Update to recommended settings**, pode clicar em **Perform Changes**. Não adicione nenhuma capacidade (Capability) depois disso.

No Xcode o projeto ainda se chama StrayScanner, porque o código nasceu desse app. No iPhone o nome que aparece é **FaleAgro LiDAR**.

## 5. Assinar com o Apple ID gratuito

Esta é a parte que costuma travar. Faça nesta ordem.

1. Na coluna da esquerda, clique no ícone azul **StrayScanner** (a primeira linha, não uma pasta).
2. No meio, em **TARGETS**, clique em **StrayScanner**. Não clique em StrayScannerTests nem em StrayScanner debug.
3. Aba **Signing & Capabilities**.
4. Marque **Automatically manage signing**.
5. Em **Team**, escolha o seu nome **(Personal Team)**.
6. O **Bundle Identifier** deve ser `com.faleagro.lidar`.
7. Se aparecer um erro vermelho dizendo que esse identificador já está em uso, apague e escreva outro, sem espaço e sem acento. Exemplo: `com.rodrigo.faleagro.lidar`.
8. Não clique no botão **+ Capability**. Não ligue notificação, iCloud, App Groups nem nada parecido. Conta gratuita não aceita isso, e este app não precisa.

Se o Xcode pedir a senha do Mac para usar o chaveiro, é a senha de ligar o computador, não a senha da Apple.

## 6. Preparar o iPhone

1. No iPhone, o cabo entra e o aparelho precisa estar desbloqueado (tela inicial, não a tela de senha).
2. Se aparecer **Confiar neste computador?**, toque em **Confiar** e digite o código do iPhone.
3. O iPhone pede o **Modo de programador** na primeira vez:
   - Abra **Ajustes → Privacidade e Segurança**.
   - Role até **Modo do Programador** (ou **Developer Mode**).
   - Esse item às vezes só aparece depois da primeira tentativa de instalar, no passo 7. Ligue o interruptor, o iPhone reinicia, e confirme **Ativar**.
4. Conecte de novo se o cabo tiver saído no reinício.

## 7. Instalar pelo cabo

1. No alto do Xcode, perto do botão de play (triângulo), tem um menu com o nome de um aparelho.
2. Clique nele e escolha o seu **iPhone**. Não escolha nada que diga Simulator ou iPhone 16 genérico cinza.
3. O esquema ao lado, se aparecer, deve ser **StrayScanner**.
4. Clique no triângulo de play. A primeira vez demora.
5. Se o iPhone avisar que o desenvolvedor não é confiável:
   - **Ajustes → Geral → VPN e Gestão de Dispositivos** (pode aparecer como **Gerenciamento de Dispositivo**).
   - Toque no seu Apple ID e em **Confiar**.
6. Abra o app **FaleAgro LiDAR** na tela de início.
7. Quando pedir a câmera, toque em **Permitir**. Sem isso a medição não abre.

O app não pede conta, não pede iCloud e não envia nada para a internet.

## 8. A instalação gratuita dura 7 dias

Com Apple ID gratuito, o iPhone apaga a permissão do app em cerca de 7 dias. O app some ou não abre. As medições já feitas continuam no aparelho se você instalar de novo por cima, com o mesmo identificador (o Bundle Identifier do passo 5).

Para reinstalar: cabo, iPhone desbloqueado, Xcode, botão de play outra vez. Não precisa pagar.

A conta gratuita também só deixa poucos apps seus ao mesmo tempo no iPhone. Se a instalação falhar por limite, apague outro app de teste que você tenha instalado do Xcode.

## 9. Medir no talhão

1. Abra o app. A primeira tela é o histórico.
2. Toque em **Nova medição**.
3. Preencha a ficha. O ponto amostral é de 1 a 5.
4. Escolha A, B ou C e leia a frase de como segurar o celular.
5. A caixinha da referência de escala é opcional e manual. Se você não viu uma referência, deixe desmarcada. Os metros continuam vindo do LiDAR. A confiança fica um pouco menor.
6. Toque em **Começar captura**.
7. A imagem é a câmera. Toque nela para ver a profundidade no lugar da cor.
8. Leia os avisos coloridos no alto. Vermelho: pare e vá mais devagar. Laranja: a captura ainda está fraca.
9. Toque no botão redondo para gravar e toque de novo para parar.
10. Espere a frase **Calculando as medidas neste iPhone**.
11. A medição volta para a lista, com o resumo e a confiança.
12. Abra a medição para ver cada número, o que ele significa, o histograma (na lateral) e as limitações.

Sugestão de campo:

- A e C: fique parado alguns segundos, na orientação certa, até o aviso de área incompleta sumir.
- B: escolha um metro de linha e dê a volta devagar, dos dois lados, sem sacudir.

## 10. Levar os arquivos para o Mac

Dentro da medição, toque em **Exportar JSON e PLY**. O iPhone abre a folha de compartilhar. Dá para usar AirDrop para o Mac, ou salvar em Arquivos. O pacote inclui:

- `metricas.json` — ficha, números, confiança e limitações
- `nuvem.ply` — nuvem de pontos em metros (eixo Y para cima). Não é folha individual
- a captura bruta: `rgb.mp4`, pastas `depth` e `confidence`, `odometry.csv`, `camera_matrix.csv`, `imu.csv`

Pelo cabo, também dá para copiar a pasta inteira: no Finder, clique no iPhone, aba **Arquivos** (ou **Files**), e arraste a pasta do app. Uma pasta por medição.

## 11. Problemas comuns

**Signing for StrayScanner requires a development team.**  
Falta o time. Volte ao passo 5 e escolha Personal Team.

**Failed to register bundle identifier** ou identificador indisponível.  
Troque o Bundle Identifier, como no passo 5. Sem espaço e sem acento.

**O iPhone não aparece na lista.**  
Cabo bem encaixado, iPhone desbloqueado, “Confiar neste computador”, e o cabo precisa passar dados (alguns cabos só carregam).

**Developer Mode disabled** ou o app não instala.  
Passo 6, Modo do Programador, reiniciar, play de novo.

**Untrusted Developer.**  
Ajustes → Geral → VPN e Gestão de Dispositivos → Confiar.

**Este iPhone não serve.**  
O aparelho não tem LiDAR. O protótipo pede o iPhone 16 Pro Max (ou outro iPhone Pro com LiDAR). iPhone 16 comum não tem esse sensor.

**A câmera fica preta.**  
Ajustes → FaleAgro LiDAR → Câmera → Permitir. Ou apague o app e instale de novo pelo cabo, e aceite a câmera.

**Escolhi um Simulator sem querer.**  
O simulador não tem LiDAR. Escolha o iPhone de verdade no menu de cima.

**Update to recommended settings.**  
Perform Changes é seguro. Não adicione Capability.

**O Xcode mostra erro vermelho numa linha de código.**  
Anote o texto do erro. Não mude o Bundle Identifier no meio de um erro de código. O alvo certo é StrayScanner, esquema StrayScanner.

## Limitações do sensor, em uma lista

- LiDAR de iPhone não resolve folha individual nem haste fina.
- Altura é a copa aparente contra o plano do chão, e só quando esse plano fica estável.
- Volume aparente é o volume sob essa superfície, por metro de linha, com o ar no meio. Não é biomassa.
- Cobertura, solo, abertura e fechamento dependem da cor. Luz ruim muda o número. A confiança cai junto.
- A escala em metros é a do ARKit. A caixinha de referência não calibra nada.
- Nada aqui serve, sozinho, para estimar saca, nitrogênio ou data de colheita.

## Créditos

Captura RGB-D: Stray Scanner, copyright Stray Robots, licença MIT (arquivo `LICENSE.md`). Este protótipo não pede login, não usa serviço pago da Apple e não manda os dados para fora do iPhone.
