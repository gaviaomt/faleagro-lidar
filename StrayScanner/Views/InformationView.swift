//
//  InformationView.swift
//  FaleAgro LiDAR
//

import SwiftUI

struct InformationView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    secao("Para que serve", """
Este protótipo mede a estrutura do dossel da soja com a câmera e o LiDAR do iPhone. Funciona sem internet. Os arquivos ficam neste aparelho.
""")
                    secao("O que ele não faz", """
Não calcula biomassa, peso, produtividade nem adubo. Não foi calibrado com balança ou laboratório. Não conta folha por folha.
""")
                    secao("Antes de gravar", """
Preencha fazenda, talhão, variedade, data de plantio, tratamento e o ponto de 1 a 5. Escolha uma modalidade:

A · Inferior — celular perto do chão, câmera para cima. Mede a abertura (céu visível) e o fechamento.

B · Lateral 3D — ande devagar ao redor de cerca de 1 m de linha. Mede altura, largura aparente, volume aparente e a distribuição vertical.

C · Superior — câmera para baixo, acima da copa. Mede cobertura de vegetação, solo exposto e, se o chão ficar confiável, a altura.
""")
                    secao("Avisos na tela", """
Muito rápido: ande ou segure mais devagar.
Rastreamento perdido ou limitado: aponte para plantas e chão, sem virar de repente.
Profundidade com confiança baixa: chegue um pouco mais perto e evite reflexo forte no sensor.
Área incompleta: a modalidade ainda não viu o bastante (tempo parado nas vistas de cima e de baixo, ou a volta de 1 m na vista lateral).
Referência de escala: é só uma caixa que você marca. O app não acha a referência sozinho.
""")
                    secao("Confiança", """
Cada número tem confiança alta, média ou baixa. Confiança baixa quer dizer que o número pode oscilar. Se o chão não ficou confiável, a altura não aparece — o app não inventa o centímetro.
""")
                    secao("O LiDAR deste iPhone", """
O sensor não separa folha individual nem haste fina. A altura é a superfície aparente da copa. O volume aparente inclui o ar entre as folhas e vem em metros cúbicos por metro de linha. Sombra forte e sol estourado mudam a cobertura e a abertura, porque elas usam a cor verde junto com a profundidade.
""")
                    secao("Exportar", """
Em cada medição, Exportar JSON e PLY monta um arquivo com metricas.json, nuvem.ply e a captura bruta (vídeo, mapas de profundidade, confiança, pose e horários). Dá para enviar pelo compartilhamento do iPhone. Também dá para copiar a pasta pelo cabo, no Finder do Mac, em Arquivos do aparelho.
""")
                    secao("Créditos", """
A captura bruta vem do Stray Scanner, de Stray Robots, licença MIT. O FaleAgro LiDAR é um protótipo em cima desse código.
""")
                }
                .padding(18)
            }
            .background(Color("BackgroundColor").ignoresSafeArea())
            .navigationTitle("Sobre")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func secao(_ titulo: String, _ texto: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titulo)
                .font(.title3.weight(.bold))
                .foregroundColor(Color("TextColor"))
            Text(texto)
                .font(.body)
                .foregroundColor(Color("TextColor"))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
