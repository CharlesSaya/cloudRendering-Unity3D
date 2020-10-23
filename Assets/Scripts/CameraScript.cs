using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class CameraScript : MonoBehaviour
{

    public Shader raymarchShader;

    public Material Material
    {
        get
        {
            if (!_EffectMaterial && raymarchShader)
            {
                _EffectMaterial = new Material(raymarchShader);
                _EffectMaterial.hideFlags = HideFlags.HideAndDontSave;
            }
            return _EffectMaterial;
        }
    }
    [SerializeField]
    private Material _EffectMaterial;

    public Camera CurrentCamera
    {
        get
        {
            if (!_CurrentCamera)
                _CurrentCamera = GetComponent<Camera>();
            return _CurrentCamera;
        }
    }
    [SerializeField]
    private Camera _CurrentCamera;


    void CustomGraphicsBlit(RenderTexture src, RenderTexture dest, Material material, int pass )
    {

        RenderTexture.active = dest;


        material.SetTexture("_MainTex",src);
        material.SetPass(pass);

        GL.PushMatrix();
        GL.LoadOrtho();


        GL.Begin(GL.QUADS);

        GL.MultiTexCoord2(0, 0.0f, 1.0f); //TL
        GL.Vertex3(0.0f, 1.0f, 1.0f);

        GL.MultiTexCoord2(0, 1.0f, 1.0f); //TR
        GL.Vertex3(1.0f, 1.0f, 2.0f);

        GL.MultiTexCoord2(0, 1.0f, 0.0f); //BR
        GL.Vertex3(1.0f, 0.0f, 3.0f);

        GL.MultiTexCoord2(0, 0.0f, 0.0f); //BL
        GL.Vertex3(0.0f, 0.0f, 0.0f);     

        GL.End();

        GL.PopMatrix();

    }

    public Transform directionalLight;
    public Light light;
 

    private float X;
    private float Y;
    float speed = 1.0f;
    float speed2 = 1.0f;
    void Update()
    {



        if (Input.GetMouseButton(0))
        {
            transform.Rotate(new Vector3(Input.GetAxis("Mouse Y") * speed2,- Input.GetAxis("Mouse X") * speed2, 0));
            X = transform.rotation.eulerAngles.x;
            Y = transform.rotation.eulerAngles.y;
            transform.rotation = Quaternion.Euler(X, Y, 0);
        }

        if (Input.GetKey(KeyCode.D))
        {
            _CurrentCamera.transform.Translate(new Vector3(speed * Time.deltaTime, 0, 0));
        }
        if (Input.GetKey(KeyCode.Q))
        {
            _CurrentCamera.transform.Translate(new Vector3(-speed * Time.deltaTime, 0, 0));
        }
        if (Input.GetKey(KeyCode.S))
        {
            _CurrentCamera.transform.Translate(new Vector3(0, 0, -speed * Time.deltaTime));
        }
        if (Input.GetKey(KeyCode.Z))
        {
            _CurrentCamera.transform.Translate(new Vector3(0, 0, speed * Time.deltaTime));
        }
    }   

    void OnRenderImage(RenderTexture src, RenderTexture dest)
    {

        if (!_EffectMaterial)
        {
            Graphics.Blit(src, dest);
        }

        Vector3[] frustrumCorners = new Vector3[4];

        _CurrentCamera.CalculateFrustumCorners(new Rect(0, 0, 1, 1), _CurrentCamera.farClipPlane, Camera.MonoOrStereoscopicEye.Mono, frustrumCorners);
      
      

       Matrix4x4 corners = Matrix4x4.identity  ;
        for(int i =0;i< frustrumCorners.Length; i++){
            corners.SetRow(i, _CurrentCamera.transform.TransformVector(frustrumCorners[i]));
        }

        _EffectMaterial.SetVector("_lightDir", directionalLight ? directionalLight.forward : Vector3.down);
        _EffectMaterial.SetMatrix("_frustrumCorners", corners);


        _EffectMaterial.SetVector("_cameraWsPos", _CurrentCamera.transform.position);
        //Graphics.Blit(src, dest);
         CustomGraphicsBlit(src, dest, _EffectMaterial,0);

        
    }
    
}
