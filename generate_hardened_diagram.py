import os, urllib.parse

ICON_DIR = r'C:\Users\DEBESURBHA\.agents\skills\drawio-mcp-diagramming\references\Azure_Public_Service_Icons\Icons'

def get_b64_svg(rel_path):
    path = os.path.join(ICON_DIR, rel_path.replace('/', '\\'))
    if not os.path.exists(path):
        print(f"Icon not found: {path}")
        return ''
    with open(path, 'r', encoding='utf-8') as f:
        svg = f.read()
    return urllib.parse.quote(svg)

icons = {
    'iiq': get_b64_svg('compute/10023-icon-service-Kubernetes-Services.svg'),
    'mssql': get_b64_svg('databases/10132-icon-service-SQL-Server.svg'),
    'mysql': get_b64_svg('databases/10122-icon-service-Azure-Database-MySQL-Server.svg'),
    'ldap': get_b64_svg('identity/10224-icon-service-Active-Directory-Connect-Health.svg'),
    'mq': get_b64_svg('integration/10836-icon-service-Azure-Service-Bus.svg'),
    'nas': get_b64_svg('storage/10086-icon-service-Storage-Accounts.svg')
}

xml_template = f'''<mxGraphModel dx="1422" dy="798" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="827" pageHeight="1169" math="0" shadow="0" adaptiveColors="auto">
  <root>
    <mxCell id="0" />
    <mxCell id="1" parent="0" />
    
    <mxCell id="tailnet" value="Tailscale Tailnet (Remote Access)" style="swimlane;whiteSpace=wrap;html=1;startSize=30;dashed=1;fillColor=light-dark(#f5f5f5,#2b2b2b);strokeColor=#999999;container=1;pointerEvents=0;" vertex="1" parent="1">
      <mxGeometry x="40" y="40" width="740" height="560" as="geometry" />
    </mxCell>

    <mxCell id="cluster" value="K3s Cluster (Homelab)" style="swimlane;whiteSpace=wrap;html=1;startSize=30;fillColor=light-dark(#e1f5fe,#1a2a3a);strokeColor=#039be5;container=1;pointerEvents=0;" vertex="1" parent="tailnet">
      <mxGeometry x="40" y="60" width="660" height="460" as="geometry" />
    </mxCell>

    <mxCell id="ns" value="Namespace: iiqstack" style="swimlane;whiteSpace=wrap;html=1;startSize=30;fillColor=light-dark(#ffffff,#121212);strokeColor=#000000;container=1;pointerEvents=0;" vertex="1" parent="cluster">
      <mxGeometry x="40" y="60" width="580" height="360" as="geometry" />
    </mxCell>

    <mxCell id="iiq_icon" value="" style="shape=image;image=data:image/svg+xml,{icons['iiq']};verticalLabelPosition=bottom;labelBackgroundColor=#ffffff;verticalAlign=top;html=1;aspect=fixed;" vertex="1" parent="ns">
      <mxGeometry x="40" y="60" width="50" height="50" as="geometry" />
    </mxCell>
    <mxCell id="iiq_label" value="IdentityIQ" style="text;html=1;align=center;verticalAlign=middle;resizable=0;points=[];autosize=1;strokeColor=none;fillColor=none;" vertex="1" parent="ns">
      <mxGeometry x="25" y="115" width="80" height="30" as="geometry" />
    </mxCell>

    <mxCell id="mssql_icon" value="" style="shape=image;image=data:image/svg+xml,{icons['mssql']};verticalLabelPosition=bottom;labelBackgroundColor=#ffffff;verticalAlign=top;html=1;aspect=fixed;" vertex="1" parent="ns">
      <mxGeometry x="240" y="60" width="50" height="50" as="geometry" />
    </mxCell>
    <mxCell id="mssql_label" value="MSSQL (db-0)" style="text;html=1;align=center;verticalAlign=middle;resizable=0;points=[];autosize=1;strokeColor=none;fillColor=none;" vertex="1" parent="ns">
      <mxGeometry x="215" y="115" width="100" height="30" as="geometry" />
    </mxCell>

    <mxCell id="mysql_icon" value="" style="shape=image;image=data:image/svg+xml,{icons['mysql']};verticalLabelPosition=bottom;labelBackgroundColor=#ffffff;verticalAlign=top;html=1;aspect=fixed;" vertex="1" parent="ns">
      <mxGeometry x="240" y="200" width="50" height="50" as="geometry" />
    </mxCell>
    <mxCell id="mysql_label" value="MySQL" style="text;html=1;align=center;verticalAlign=middle;resizable=0;points=[];autosize=1;strokeColor=none;fillColor=none;" vertex="1" parent="ns">
      <mxGeometry x="235" y="255" width="60" height="30" as="geometry" />
    </mxCell>

    <mxCell id="ldap_icon" value="" style="shape=image;image=data:image/svg+xml,{icons['ldap']};verticalLabelPosition=bottom;labelBackgroundColor=#ffffff;verticalAlign=top;html=1;aspect=fixed;" vertex="1" parent="ns">
      <mxGeometry x="440" y="60" width="50" height="50" as="geometry" />
    </mxCell>
    <mxCell id="ldap_label" value="OpenLDAP" style="text;html=1;align=center;verticalAlign=middle;resizable=0;points=[];autosize=1;strokeColor=none;fillColor=none;" vertex="1" parent="ns">
      <mxGeometry x="425" y="115" width="80" height="30" as="geometry" />
    </mxCell>

    <mxCell id="mq_icon" value="" style="shape=image;image=data:image/svg+xml,{icons['mq']};verticalLabelPosition=bottom;labelBackgroundColor=#ffffff;verticalAlign=top;html=1;aspect=fixed;" vertex="1" parent="ns">
      <mxGeometry x="440" y="200" width="50" height="50" as="geometry" />
    </mxCell>
    <mxCell id="mq_label" value="ActiveMQ" style="text;html=1;align=center;verticalAlign=middle;resizable=0;points=[];autosize=1;strokeColor=none;fillColor=none;" vertex="1" parent="ns">
      <mxGeometry x="425" y="255" width="80" height="30" as="geometry" />
    </mxCell>

    <mxCell id="nas_icon" value="" style="shape=image;image=data:image/svg+xml,{icons['nas']};verticalLabelPosition=bottom;labelBackgroundColor=#ffffff;verticalAlign=top;html=1;aspect=fixed;" vertex="1" parent="cluster">
      <mxGeometry x="40" y="440" width="50" height="50" as="geometry" />
    </mxCell>
    <mxCell id="nas_label" value="QNAP NAS (192.168.0.128)" style="text;html=1;align=left;verticalAlign=middle;resizable=0;points=[];autosize=1;strokeColor=none;fillColor=none;" vertex="1" parent="cluster">
      <mxGeometry x="100" y="450" width="160" height="30" as="geometry" />
    </mxCell>

    <mxCell id="e1" value="JDBC" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;exitX=1;exitY=0.5;entryX=0;entryY=0.5;strokeWidth=2;strokeColor=#0078D4;" edge="1" parent="ns" source="iiq_icon" target="mssql_icon">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <mxCell id="e2" value="" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;exitX=0.5;exitY=1;entryX=0;entryY=0.5;strokeWidth=2;strokeColor=#0078D4;" edge="1" parent="ns" source="iiq_icon" target="mysql_icon">
      <mxGeometry relative="1" as="geometry">
        <Array as="points">
          <mxPoint x="65" y="225" />
        </Array>
      </mxGeometry>
    </mxCell>

    <mxCell id="e3" value="LDAP" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;exitX=1;exitY=0.5;entryX=0;entryY=0.5;strokeWidth=2;strokeColor=#0078D4;" edge="1" parent="ns" source="mssql_icon" target="ldap_icon">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <mxCell id="e4" value="JMS" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;exitX=1;exitY=0.5;entryX=0;entryY=0.5;strokeWidth=2;strokeColor=#0078D4;" edge="1" parent="ns" source="mysql_icon" target="mq_icon">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <mxCell id="s1" value="Persistent Volume Claims (NFS)" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;exitX=0.5;exitY=1;entryX=0.5;entryY=0;dashed=1;strokeWidth=1;strokeColor=#999999;" edge="1" parent="cluster" source="ns" target="nas_icon">
      <mxGeometry relative="1" as="geometry">
        <Array as="points">
          <mxPoint x="330" y="430" />
          <mxPoint x="65" y="430" />
        </Array>
      </mxGeometry>
    </mxCell>

  </root>
</mxGraphModel>'''

with open('iiqstack_hardened.drawio', 'w', encoding='utf-8') as f:
    f.write(xml_template)
print("File generated successfully.")
